let src = Logs.Src.create "user_import.service"
let get_or_failwith = Pool_common.Utils.get_or_failwith
let interval_s = 15 * 60
let limit = 50 (* equals 4'800 emails a day *)

let run database_label =
  let open Utils.Lwt_result.Infix in
  let%lwt import_message =
    let%lwt tenant =
      Pool_tenant.find_by_label database_label ||> get_or_failwith
    in
    Message_template.UserImport.prepare database_label tenant
  in
  let to_admin = CCList.map (fun (admin, import) -> `Admin admin, import) in
  let to_contact =
    CCList.map (fun (contact, import) -> `Contact contact, import)
  in
  let run_limit fcn decode limit = fcn database_label limit () ||> decode in
  let tasks =
    [ run_limit Repo.find_admins_to_notify to_admin, Event.notified
    ; run_limit Repo.find_contacts_to_notify to_contact, Event.notified
    ; run_limit Repo.find_admins_to_remind to_admin, Event.reminded
    ; run_limit Repo.find_contacts_to_remind to_contact, Event.reminded
    ]
  in
  let make_events (messages, events) (contact, import) event_fnc =
    let message = import_message contact import.Entity.token in
    let event = event_fnc import in
    (message, None) :: messages, event :: events
  in
  let rec folder limit tasks events =
    if limit <= 0
    then Lwt.return events
    else (
      match tasks with
      | [] -> Lwt.return events
      | (repo_fnc, event_fnc) :: tl ->
        let%lwt users = repo_fnc limit in
        let new_limit = limit - CCList.length users in
        CCList.fold_left
          (fun events data -> make_events events data event_fnc)
          events
          users
        |> folder new_limit tl)
  in
  let%lwt emails, import_events = folder limit tasks ([], []) in
  let%lwt () = Email.(BulkSent emails |> handle_event database_label) in
  import_events |> Lwt_list.iter_s (Event.handle_event database_label)
;;

let run_all () =
  let open Utils.Lwt_result.Infix in
  Pool_tenant.find_databases ()
  >|> Lwt_list.iter_s (fun { Pool_database.label; _ } -> run label)
;;

let start () =
  let open Schedule in
  let interval = Ptime.Span.of_int_s interval_s in
  let periodic_fcn () =
    Logs.debug ~src (fun m ->
      m ~tags:Pool_database.(Logger.Tags.create root) "Run");
    run_all ()
  in
  create
    "import_notifications"
    (Every (interval |> ScheduledTimeSpan.of_span))
    periodic_fcn
  |> Schedule.add_and_start
;;

let stop () = Lwt.return_unit

let lifecycle =
  Sihl.Container.create_lifecycle
    "System events"
    ~dependencies:(fun () ->
      [ Database.lifecycle; Email.Service.Queue.lifecycle ])
    ~start
    ~stop
;;

let register () = Sihl.Container.Service.create lifecycle
