let get_or_failwith = Pool_common.Utils.get_or_failwith

let count_of_rate interval rate =
  (* calculated number of invitations from the rate per hour -> runns every
     <interval> minutes *)
  if interval > 60 || interval < 1
  then Result.error Pool_common.Message.(Invalid Field.Interval)
  else
    CCFloat.(of_int (Mailing.Rate.value rate) / 60.0 * of_int interval |> round)
    |> CCInt.of_float
    |> Result.ok
;;

let i18n_templates pool { Experiment.invitation_template; _ } languages =
  let open Utils.Lwt_result.Infix in
  let open Experiment.InvitationTemplate in
  let open I18n in
  Lwt_list.map_s
    (fun language ->
      let%lwt subject =
        find_by_key pool Key.InvitationSubject language ||> get_or_failwith
      in
      let%lwt text =
        find_by_key pool Key.InvitationText language ||> get_or_failwith
      in
      let subject =
        invitation_template
        |> CCOption.map_or ~default:subject (fun { subject; _ } ->
             subject
             |> Subject.value
             |> Content.of_string
             |> create Key.InvitationSubject language)
      in
      let text =
        invitation_template
        |> CCOption.map_or ~default:text (fun { text; _ } ->
             text
             |> Text.value
             |> Content.of_string
             |> create Key.ImportInvitationText language)
      in
      (language, (subject, text)) |> Lwt.return)
    languages
;;

let find_contacts_by_mailing
  pool
  ?(interval = 5)
  { Mailing.id; rate; distribution; _ }
  =
  let open Utils.Lwt_result.Infix in
  let%lwt ({ Experiment.id; filter; _ } as experiment) =
    Experiment.find_of_mailing pool (id |> Mailing.Id.to_common)
    ||> get_or_failwith
  in
  let n_new_invitations = rate |> count_of_rate interval |> get_or_failwith in
  let order_by =
    distribution
    |> CCOption.map_or ~default:"" Mailing.Distribution.get_order_element
  in
  let%lwt contacts =
    Contact.find_filtered ~order_by ~limit:n_new_invitations pool id filter
  in
  let%lwt i18n_templates =
    i18n_templates pool experiment Pool_common.Language.all
  in
  (experiment, contacts, [], i18n_templates) |> Lwt.return
;;
