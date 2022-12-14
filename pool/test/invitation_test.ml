module InvitationCommand = Cqrs_command.Invitation_command
module Field = Pool_common.Message.Field
module Model = Test_utils.Model

let create_invitation () =
  let contact = Model.create_contact () in
  Invitation.
    { id = Pool_common.Id.create ()
    ; contact
    ; resent_at = None
    ; created_at = Pool_common.CreatedAt.create ()
    ; updated_at = Pool_common.UpdatedAt.create ()
    }
;;

let create () =
  let experiment = Model.create_experiment () in
  let tenant = Tenant_test.Data.full_tenant |> CCResult.get_exn in
  let contact = Model.create_contact () in
  let languages = Pool_common.Language.all in
  let i18n_templates = Test_utils.i18n_templates languages in
  let events =
    let command =
      InvitationCommand.Create.
        { experiment; contacts = [ contact ]; invited_contacts = [] }
    in
    InvitationCommand.Create.handle command tenant languages i18n_templates
  in
  let expected =
    let email =
      let open Pool_common.Language in
      let subject, text = CCList.assoc ~eq:equal En i18n_templates in
      let layout = Email.Helper.layout_from_tenant tenant in
      ( contact.Contact.user
      , Invitation.email_experiment_elements experiment
      , Email.CustomTemplate.
          { subject = Subject.I18n subject
          ; content = Content.I18n text
          ; layout
          } )
      |> CCList.pure
    in
    Ok
      [ Invitation.(Created ([ contact ], experiment)) |> Pool_event.invitation
      ; Email.InvitationBulkSent email |> Pool_event.email
      ; Contact.NumInvitationsIncreased contact |> Pool_event.contact
      ]
  in
  Test_utils.check_result expected events
;;

let resend () =
  let open InvitationCommand.Resend in
  let tenant = Tenant_test.Data.full_tenant |> CCResult.get_exn in
  let invitation = create_invitation () in
  let experiment = Model.create_experiment () in
  let languages = Pool_common.Language.all in
  let i18n_templates = Test_utils.i18n_templates languages in
  let events =
    handle { invitation; experiment } tenant languages i18n_templates
  in
  let expected =
    let open CCResult in
    let* email =
      InvitationCommand.invitation_template_elements
        tenant
        languages
        i18n_templates
        experiment
        invitation.Invitation.contact.Contact.language
    in
    Ok
      [ Invitation.(Resent invitation) |> Pool_event.invitation
      ; Email.InvitationSent
          ( invitation.Invitation.contact.Contact.user
          , Invitation.email_experiment_elements experiment
          , email )
        |> Pool_event.email
      ]
  in
  Test_utils.check_result expected events
;;
