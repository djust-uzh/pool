open CCFun
include Entity
module Guard = Entity_guard

let src = Logs.Src.create "schedule.service"
let tags = Pool_database.(Logger.Tags.create root)

module Registered = struct
  module ScheduleMap = CCMap.Make (Label)

  type t = Entity.t

  let registered : t ScheduleMap.t ref = ref ScheduleMap.empty

  let iter_lwt fcn =
    !registered
    |> ScheduleMap.to_list
    |> Lwt_list.iter_s (fun (_, schedule) -> fcn schedule)
  ;;

  let store label = ScheduleMap.find label !registered |> Repo.upsert

  let store_all () =
    !registered |> ScheduleMap.to_list |> Lwt_list.iter_s (snd %> Repo.upsert)
  ;;

  let add_base ({ label; _ } as schedule : t) =
    Logs.debug ~src (fun m -> m ~tags "registered '%s'" label);
    registered := ScheduleMap.add label schedule !registered
  ;;

  let add ({ label; _ } as schedule : t) =
    add_base schedule;
    store label
  ;;

  let update_status status ({ label; _ } : t) =
    let update_status = CCOption.map (fun (s : t) -> { s with status }) in
    registered := ScheduleMap.update label update_status !registered;
    store label
  ;;

  let update_last_run_base ({ label; _ } : t) =
    let last_run = Some (LastRunAt.create_now ()) in
    let add_last_run = CCOption.map (fun (s : t) -> { s with last_run }) in
    registered := ScheduleMap.update label add_last_run !registered
  ;;

  let update_last_run ({ label; _ } as schedule : t) =
    update_last_run_base schedule;
    store label
  ;;

  let finish_base ({ label; _ } : t) =
    let open ScheduleMap in
    let add_finished =
      CCOption.map (fun schedule : Entity.t ->
        let last_run = Some (LastRunAt.create_now ()) in
        let status = Status.Finished in
        { schedule with last_run; status })
    in
    registered := update label add_finished !registered
  ;;

  let finish ({ label; _ } as schedule : t) =
    let () = finish_base schedule in
    let%lwt () = store label in
    let () = registered := ScheduleMap.remove label !registered in
    Lwt.return_unit
  ;;

  let update_run_status schedule = function
    | Every _ -> update_last_run schedule
    | At _ -> finish schedule
  ;;

  let stop_all_active () =
    let open ScheduleMap in
    let stop_if_active ({ status; _ } as schedule : Entity.t) =
      if Status.(equal Active) status
      then { schedule with status = Status.Stopped }
      else schedule
    in
    registered := map stop_if_active !registered;
    store_all ()
  ;;
end

let run ({ label; scheduled_time; status; _ } as schedule : t) =
  let open Utils.Lwt_result.Infix in
  let delay = run_in scheduled_time in
  let paused () =
    Logs.debug ~src (fun m -> m ~tags "%s: Run is paused" label);
    Lwt.return_unit
  in
  let run ({ label; scheduled_time; fcn; _ } as schedule) =
    Logs.debug ~src (fun m -> m ~tags "%s: Run in %f seconds" label delay);
    let%lwt () =
      Lwt.catch
        (fun () -> fcn ())
        (fun exn ->
          Logs.err ~src (fun m ->
            m
              ~tags
              "Exception caught while running schedule:\n %s"
              (Printexc.to_string exn));
          Lwt.return_unit)
    in
    Registered.update_run_status schedule scheduled_time
  in
  let rec loop () : unit Lwt.t =
    let process schedule =
      let%lwt () = run schedule in
      Lwt_unix.sleep delay >|> loop
    in
    let open Status in
    match scheduled_time, status with
    | Every _, Active -> process schedule
    | At time, Active when Ptime.is_later ~than:(Ptime_clock.now ()) time ->
      let%lwt () = Registered.update_status Status.Running schedule in
      process schedule
    | (Every _ | At _), Paused -> paused ()
    | (Every _ | At _), (Active | Finished | Running | Stopped) ->
      Lwt.return_unit
  in
  loop ()
;;

let start_schedule ({ label; _ } as schedule : t) =
  Logs.info ~src (fun m -> m ~tags "Start %s" label);
  Lwt.ignore_result @@ run schedule;
  Lwt.return_unit
;;

let start () =
  let%lwt () = Repo.stop_all_active () in
  Logs.info ~src (fun m -> m ~tags "Start schedule");
  Registered.iter_lwt start_schedule
;;

let stop = Registered.stop_all_active
let lifecycle = Sihl.Container.create_lifecycle "pool schedule" ~start ~stop

let register ?(schedules = []) () =
  CCList.iter Registered.add_base schedules;
  Sihl.Container.Service.create lifecycle
;;

let add_and_start schedule =
  let%lwt () = Registered.add schedule in
  start_schedule schedule
;;

let find_all = Repo.find_all
let find_by = Repo.find_by
