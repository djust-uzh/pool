module Data = struct
  let database_label = "econ-test" |> Pool_database.Label.of_string
end

(* Testable *)
let event = Alcotest.testable Pool_event.pp Pool_event.equal

let tenant_smtp_auth =
  Alcotest.testable Pool_tenant.SmtpAuth.pp Pool_tenant.SmtpAuth.equal
;;

let error =
  Alcotest.testable Pool_common.Message.pp_error Pool_common.Message.equal_error
;;

let contact = Alcotest.testable Contact.pp Contact.equal

(* Helper functions *)

let setup_test () =
  let open Sihl.Configuration in
  let file_configuration = read_env_file () in
  let () = store @@ CCOption.value file_configuration ~default:[] in
  let () = Logs.set_level (Some Logs.Error) in
  let () = Logs.set_reporter Sihl.Log.default_reporter in
  Lwt.return_unit
;;

let get_or_failwith_pool_error res =
  res
  |> CCResult.map_err Pool_common.(Utils.error_to_string Language.En)
  |> CCResult.get_or_failwith
;;

let file_to_storage file =
  let open Database.SeedAssets in
  let stored_file =
    Sihl_storage.
      { id = file.Database.SeedAssets.id
      ; filename = file.filename
      ; filesize = file.filesize
      ; mime = file.mime
      }
  in
  let base64 = Base64.encode_exn file.body in
  let%lwt _ = Service.Storage.upload_base64 stored_file base64 in
  Lwt.return_unit
;;

let dummy_to_file (dummy : Database.SeedAssets.file) =
  let open Database.SeedAssets in
  let open Pool_common in
  let get_or_failwith res =
    res
    |> CCResult.map_err (Utils.error_to_string Language.En)
    |> CCResult.get_or_failwith
  in
  let name = File.Name.create dummy.filename |> get_or_failwith in
  let filesize = File.Size.create dummy.filesize |> get_or_failwith in
  let mime_type = File.Mime.of_string dummy.mime |> get_or_failwith in
  File.
    { id = dummy.id |> Id.of_string
    ; name
    ; size = filesize
    ; mime_type
    ; created_at = Ptime_clock.now ()
    ; updated_at = Ptime_clock.now ()
    }
;;

let create_contact () =
  Contact.
    { user =
        Sihl_user.
          { id = Pool_common.Id.(create () |> value)
          ; email = "test@econ.uzh.ch"
          ; username = None
          ; name = None
          ; given_name = None
          ; password =
              "somepassword"
              |> Sihl_user.Hashing.hash
              |> CCResult.get_or_failwith
          ; status =
              Sihl_user.status_of_string "active" |> CCResult.get_or_failwith
          ; admin = false
          ; confirmed = true
          ; created_at = Pool_common.CreatedAt.create ()
          ; updated_at = Pool_common.UpdatedAt.create ()
          }
    ; recruitment_channel = RecruitmentChannel.Friend
    ; terms_accepted_at = Pool_user.TermsAccepted.create_now ()
    ; language = Some Pool_common.Language.En
    ; paused = Pool_user.Paused.create false
    ; disabled = Pool_user.Disabled.create false
    ; verified = Pool_user.Verified.create None
    ; email_verified =
        Pool_user.EmailVerified.create (Some (Ptime_clock.now ()))
    ; num_invitations = NumberOfInvitations.init
    ; num_assignments = NumberOfAssignments.init
    ; firstname_version = Pool_common.Version.create ()
    ; lastname_version = Pool_common.Version.create ()
    ; paused_version = Pool_common.Version.create ()
    ; language_version = Pool_common.Version.create ()
    ; created_at = Pool_common.CreatedAt.create ()
    ; updated_at = Pool_common.UpdatedAt.create ()
    }
;;

let create_public_experiment () =
  let show_error err = Pool_common.(Utils.error_to_string Language.En err) in
  Experiment.Public.
    { id = Pool_common.Id.create ()
    ; description =
        Experiment.Description.create "A description for everyone"
        |> CCResult.map_err show_error
        |> CCResult.get_or_failwith
    ; waiting_list_disabled = false |> Experiment.WaitingListDisabled.create
    ; direct_registration_disabled =
        false |> Experiment.DirectRegistrationDisabled.create
    }
;;

let create_experiment () =
  let show_error err = Pool_common.(Utils.error_to_string Language.En err) in
  Experiment.
    { id = Pool_common.Id.create ()
    ; title =
        Title.create "An Experiment"
        |> CCResult.map_err show_error
        |> CCResult.get_or_failwith
    ; description =
        Description.create "A description for everyone"
        |> CCResult.map_err show_error
        |> CCResult.get_or_failwith
    ; filter = "1=1"
    ; waiting_list_disabled = true |> WaitingListDisabled.create
    ; direct_registration_disabled = false |> DirectRegistrationDisabled.create
    ; created_at = Ptime_clock.now ()
    ; updated_at = Ptime_clock.now ()
    }
;;

let create_waiting_list () =
  let contact = create_contact () in
  let experiment = create_experiment () in
  Waiting_list.
    { id = Pool_common.Id.create ()
    ; contact
    ; experiment
    ; comment = None
    ; created_at = Pool_common.CreatedAt.create ()
    ; updated_at = Pool_common.UpdatedAt.create ()
    }
;;

let create_waiting_list_from_experiment_and_contact experiment contact =
  Waiting_list.
    { id = Pool_common.Id.create ()
    ; contact
    ; experiment
    ; comment = None
    ; created_at = Pool_common.CreatedAt.create ()
    ; updated_at = Pool_common.UpdatedAt.create ()
    }
;;

let create_session () =
  let hour = Ptime.Span.of_int_s @@ (60 * 60) in
  Session.
    { id = Pool_common.Id.create ()
    ; start =
        Ptime.add_span (Ptime_clock.now ()) hour
        |> CCOption.get_exn_or "Invalid start"
        |> Start.create
        |> Pool_common.Utils.get_or_failwith
    ; duration = Duration.create hour |> Pool_common.Utils.get_or_failwith
    ; description = None
    ; max_participants =
        ParticipantAmount.create 30 |> Pool_common.Utils.get_or_failwith
    ; min_participants =
        ParticipantAmount.create 1 |> Pool_common.Utils.get_or_failwith
    ; overbook = ParticipantAmount.create 4 |> Pool_common.Utils.get_or_failwith
    ; assignments_count =
        0 |> AssignmentCount.create |> Pool_common.Utils.get_or_failwith
    ; canceled_at = None
    ; created_at = Pool_common.CreatedAt.create ()
    ; updated_at = Pool_common.UpdatedAt.create ()
    }
;;

let creat_public_session () =
  let Session.
        { id
        ; start
        ; duration
        ; description
        ; max_participants
        ; min_participants
        ; overbook
        ; assignments_count
        ; canceled_at
        ; _
        }
    =
    create_session ()
  in
  Session.Public.
    { id
    ; start
    ; duration
    ; description
    ; max_participants
    ; min_participants
    ; overbook
    ; assignments_count
    ; canceled_at
    }
;;

let fully_book_session session =
  let get_or_failwith = Pool_common.Utils.get_or_failwith in
  Session.
    { session with
      max_participants = ParticipantAmount.create 5 |> get_or_failwith
    ; min_participants = ParticipantAmount.create 0 |> get_or_failwith
    ; overbook = ParticipantAmount.create 0 |> get_or_failwith
    ; assignments_count = 5 |> AssignmentCount.create |> get_or_failwith
    }
;;

let fully_book_public_session session =
  Session.Public.
    { session with
      max_participants =
        Session.ParticipantAmount.create 5 |> Pool_common.Utils.get_or_failwith
    ; min_participants =
        Session.ParticipantAmount.create 0 |> Pool_common.Utils.get_or_failwith
    ; overbook =
        Session.ParticipantAmount.create 0 |> Pool_common.Utils.get_or_failwith
    ; assignments_count =
        5 |> Session.AssignmentCount.create |> Pool_common.Utils.get_or_failwith
    }
;;

let create_assignment () =
  Assignment.
    { id = Pool_common.Id.create ()
    ; contact = create_contact ()
    ; show_up = ShowUp.init
    ; participated = Participated.init
    ; matches_filter = MatchesFilter.init
    ; canceled_at = CanceledAt.init
    ; created_at = Pool_common.CreatedAt.create ()
    ; updated_at = Pool_common.UpdatedAt.create ()
    }
;;
