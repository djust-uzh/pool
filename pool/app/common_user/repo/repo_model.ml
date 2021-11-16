open Entity

module Paused = struct
  include Paused

  let t = Caqti_type.bool
end

module Disabled = struct
  include Disabled

  let t = Caqti_type.bool
end

module TermsAccepted = struct
  include TermsAccepted

  let t = Caqti_type.(option ptime)
end

module Verified = struct
  include Verified

  let t = Caqti_type.(option ptime)
end

module Email = struct
  open Email

  module Token = struct
    include Email.Token

    let t = Caqti_type.(string)
  end

  module Address = struct
    include Email.Address

    let t = Caqti_type.(string)
  end

  module VerifiedAt = struct
    include Email.VerifiedAt

    let t = Caqti_type.(ptime)
  end

  let unverified_t =
    let encode (Unverified m) =
      Ok (m.address, m.token, m.created_at, m.updated_at)
    in
    let decode (address, token, created_at, updated_at) =
      Ok (Unverified { address; token; created_at; updated_at })
    in
    Caqti_type.(
      custom
        ~encode
        ~decode
        (tup4
           Address.t
           Token.t
           Pool_common.Repo.CreatedAt.t
           Pool_common.Repo.UpdatedAt.t))
  ;;

  let verified_t =
    let encode (Verified m) =
      Ok (m.address, m.verified_at, m.created_at, m.updated_at)
    in
    let decode (address, verified_at, created_at, updated_at) =
      Ok (Verified { address; verified_at; created_at; updated_at })
    in
    Caqti_type.(
      custom
        ~encode
        ~decode
        (tup4
           Address.t
           VerifiedAt.t
           Pool_common.Repo.CreatedAt.t
           Pool_common.Repo.UpdatedAt.t))
  ;;
end

module User = struct
  let status =
    let encode m = m |> Sihl_user.status_to_string |> CCResult.pure in
    let decode = Sihl_user.status_of_string in
    Caqti_type.(custom ~encode ~decode string)
  ;;

  let user_type ~encode ~decode =
    Caqti_type.(
      custom
        ~encode
        ~decode
        (tup2
           string
           (tup2
              string
              (tup2
                 (option string)
                 (tup2
                    (option string)
                    (tup2
                       (option string)
                       (tup2
                          string
                          (tup2
                             status
                             (tup2 bool (tup2 bool (tup2 ptime ptime)))))))))))
  ;;

  let encode m =
    let open Sihl.Contract.User in
    Ok
      ( m.id
      , ( m.email
        , ( m.username
          , ( m.name
            , ( m.given_name
              , ( m.password
                , ( m.status
                  , (m.admin, (m.confirmed, (m.created_at, m.updated_at))) ) )
              ) ) ) ) )
  ;;

  let user_caqti =
    let open Sihl.Contract.User in
    let decode
        ( id
        , ( email
          , ( username
            , ( name
              , ( given_name
                , ( password
                  , (status, (admin, (confirmed, (created_at, updated_at)))) )
                ) ) ) ) )
      =
      Ok
        { id
        ; email
        ; username
        ; name
        ; given_name
        ; password
        ; status
        ; admin
        ; confirmed
        ; created_at
        ; updated_at
        }
    in
    user_type ~encode ~decode
  ;;
end
