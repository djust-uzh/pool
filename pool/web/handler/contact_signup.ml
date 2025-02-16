module Command = Cqrs_command.Contact_command
module UserCommand = Cqrs_command.User_command
module HttpUtils = Http_utils

let src = Logs.Src.create "handler.contact.signup"
let create_layout = Contact_general.create_layout

let sign_up req =
  let result ({ Pool_context.database_label; language; _ } as context) =
    let open Utils.Lwt_result.Infix in
    Utils.Lwt_result.map_error (fun err -> err, "/index")
    @@
    let flash_fetcher key = Sihl.Web.Flash.find key req in
    let%lwt custom_fields =
      Custom_field.all_prompted_on_registration database_label
    in
    let%lwt terms =
      I18n.find_by_key database_label I18n.Key.TermsAndConditions language
    in
    Page.Contact.sign_up terms custom_fields context flash_fetcher
    |> create_layout req ~active_navigation:"/signup" context
    >|+ Sihl.Web.Response.of_html
  in
  result |> HttpUtils.extract_happy_path ~src req
;;

let sign_up_create req =
  let open Utils.Lwt_result.Infix in
  let open Pool_common.Message in
  let terms_key = Field.(TermsAccepted |> show) in
  let user_id = Pool_common.Id.create () in
  let%lwt urlencoded =
    Sihl.Web.Request.to_urlencoded req
    ||> HttpUtils.remove_empty_values
    ||> HttpUtils.format_request_boolean_values [ terms_key ]
  in
  let result { Pool_context.database_label; query_language; language; _ } =
    let open Utils.Lwt_result.Infix in
    let tags = Pool_context.Logger.Tags.req req in
    Utils.Lwt_result.map_error (fun msg ->
      msg, "/signup", [ HttpUtils.urlencoded_to_flash urlencoded ])
    @@ let* () = Helpers.terms_and_conditions_accepted urlencoded in
       let%lwt allowed_email_suffixes =
         let open Utils.Lwt_result.Infix in
         Settings.find_email_suffixes database_label
         ||> fun suffixes ->
         if CCList.is_empty suffixes then None else Some suffixes
       in
       let* answered_custom_fields =
         Custom_field.all_prompted_on_registration database_label
         >|> Helpers_custom_field.answer_and_validate_multiple
               req
               urlencoded
               language
               user_id
       in
       let tenant = Pool_context.Tenant.get_tenant_exn req in
       let* email_address =
         Sihl.Web.Request.urlencoded Field.(Email |> show) req
         ||> CCOption.to_result ContactSignupInvalidEmail
         >== Pool_user.EmailAddress.create
       in
       let log_request () =
         Logging_helper.log_request_with_ip
           ~src
           "User registration"
           req
           tags
           email_address
       in
       let create_contact_events () =
         let open Command.SignUp in
         let* ({ firstname; lastname; _ } as decoded) =
           decode urlencoded |> Lwt_result.lift
         in
         let%lwt token = Email.create_token database_label email_address in
         let%lwt verification_mail =
           Message_template.SignUpVerification.create
             database_label
             (CCOption.value ~default:language query_language)
             tenant
             email_address
             token
             firstname
             lastname
         in
         decoded
         |> handle
              ~tags
              ?allowed_email_suffixes
              ~user_id
              answered_custom_fields
              token
              email_address
              verification_mail
              query_language
         |> Lwt_result.lift
       in
       let%lwt existing_user =
         Service.User.find_by_email_opt
           ~ctx:(Pool_database.to_ctx database_label)
           (Pool_user.EmailAddress.value email_address)
       in
       let* events =
         match existing_user with
         | None ->
           let* events = create_contact_events () in
           log_request ();
           Lwt_result.return events
         | Some user when Service.User.is_admin user -> Lwt_result.return []
         | Some _ ->
           let%lwt contact =
             email_address |> Contact.find_by_email database_label
           in
           let* events =
             contact
             |> function
             | Ok contact when contact.Contact.user.Sihl_user.confirmed ->
               let%lwt send_notification =
                 Contact.should_send_registration_attempt_notification
                   database_label
                   contact
               in
               if not send_notification
               then Lwt_result.return []
               else
                 contact
                 |> Contact.user
                 |> Message_template.ContactRegistrationAttempt.create
                      database_label
                      (CCOption.value
                         ~default:language
                         contact.Contact.language)
                      tenant
                 ||> Command.SendRegistrationAttemptNotifitacion.handle
                       ~tags
                       contact
             | Ok contact ->
               let* create_contact_events = create_contact_events () in
               let open CCResult.Infix in
               contact
               |> Command.DeleteUnverified.handle ~tags
               >|= CCFun.flip CCList.append create_contact_events
               |> Lwt_result.lift
             | Error _ -> Lwt_result.return []
           in
           log_request ();
           Lwt_result.return events
       in
       let%lwt () = Pool_event.handle_events ~tags database_label events in
       HttpUtils.(
         redirect_to_with_actions
           (path_with_language query_language "/email-confirmation")
           [ Message.set
               ~success:[ Pool_common.Message.EmailConfirmationMessage ]
           ])
       |> Lwt_result.ok
  in
  result |> HttpUtils.extract_happy_path_with_actions ~src req
;;

let email_verification req =
  let open Utils.Lwt_result.Infix in
  let tags = Pool_context.Logger.Tags.req req in
  let result ({ Pool_context.database_label; query_language; _ } as context) =
    let open Pool_common.Message in
    let%lwt redirect_path =
      let user =
        Pool_context.find_contact context
        |> CCResult.map (fun contact -> contact.Contact.user)
        |> CCOption.of_result
      in
      match user with
      | None -> "/login" |> Lwt.return
      | Some user ->
        let open Pool_context in
        user_of_sihl_user database_label user ||> dashboard_path
    in
    (let* token =
       Sihl.Web.Request.query Field.(show Token) req
       |> CCOption.map Email.Token.create
       |> CCOption.to_result Field.(NotFound Token)
       |> Lwt_result.lift
     in
     let ctx = Pool_database.to_ctx database_label in
     let* email =
       Service.Token.read
         ~ctx
         (Email.Token.value token)
         ~k:Field.(Email |> show)
       ||> CCOption.to_result TokenInvalidFormat
       >== Pool_user.EmailAddress.create
       >>= Email.find_unverified_by_address database_label
       |> Lwt_result.map_error (fun _ -> Field.(Invalid Token))
     in
     let* events =
       let open UserCommand in
       let%lwt admin =
         Admin.find
           database_label
           (email |> Email.user_id |> Pool_common.Id.value |> Admin.Id.of_string)
       in
       let%lwt contact = Contact.find database_label (Email.user_id email) in
       let verify_email user =
         VerifyEmail.(handle ~tags user email) |> Lwt_result.lift
       in
       let update_email user =
         UpdateEmail.(handle ~tags user email) |> Lwt_result.lift
       in
       match email |> Email.user_is_confirmed, contact, admin with
       | false, Ok contact, _ -> verify_email (Contact contact)
       | true, Ok contact, _ -> update_email (Contact contact)
       | false, Error _, Ok admin -> verify_email (Admin admin)
       | true, _, Ok admin -> update_email (Admin admin)
       | true, Error _, Error _ | false, Error _, Error _ ->
         Logs.err (fun m ->
           m
             ~tags
             "Impossible email update tried: %s with context: %s"
             ([%show: Email.t] email)
             ([%show: Pool_context.t] context));
         Lwt.return_ok []
     in
     let%lwt () = Pool_event.handle_events ~tags database_label events in
     HttpUtils.(
       redirect_to_with_actions
         (path_with_language query_language redirect_path)
         [ Message.set ~success:[ EmailVerified ] ])
     |> Lwt_result.ok)
    >|- fun msg -> msg, redirect_path
  in
  result |> HttpUtils.extract_happy_path ~src req
;;

let terms req =
  let open Utils.Lwt_result.Infix in
  let result ({ Pool_context.database_label; language; _ } as context) =
    Utils.Lwt_result.map_error (fun err -> err, "/login")
    @@ let* contact = Pool_context.find_contact context |> Lwt_result.lift in
       let%lwt terms =
         I18n.find_by_key database_label I18n.Key.TermsAndConditions language
       in
       let notification =
         req
         |> Sihl.Web.Request.query "redirected"
         |> CCOption.map
              (CCFun.const Pool_common.I18n.TermsAndConditionsUpdated)
       in
       Page.Contact.terms
         ?notification
         Contact.(contact |> id |> Pool_common.Id.value)
         terms
         context
       |> create_layout req context
       >|+ Sihl.Web.Response.of_html
  in
  result |> HttpUtils.extract_happy_path ~src req
;;

let terms_accept req =
  let result { Pool_context.database_label; query_language; _ } =
    Utils.Lwt_result.map_error (fun msg -> msg, "/login")
    @@
    let open Utils.Lwt_result.Infix in
    let tags = Pool_context.Logger.Tags.req req in
    let id =
      Pool_common.(
        Sihl.Web.Router.param req Message.Field.(Id |> show) |> Id.of_string)
    in
    let* contact = Contact.find database_label id in
    let* events =
      Command.AcceptTermsAndConditions.handle ~tags contact |> Lwt_result.lift
    in
    let%lwt () = Pool_event.handle_events ~tags database_label events in
    HttpUtils.(redirect_to (path_with_language query_language "/experiments"))
    |> Lwt_result.ok
  in
  result |> HttpUtils.extract_happy_path ~src req
;;
