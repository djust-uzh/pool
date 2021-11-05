module Language : sig
  type t

  val equal : t -> t -> bool
  val pp : Format.formatter -> t -> unit
  val show : t -> string
  val code : t -> string
  val of_string : string -> (t, string) result
  val t : t Caqti_type.t
  val label : t -> string
  val schema : unit -> ('a, t) Conformist.Field.t
  val all : unit -> t list
  val all_codes : unit -> string list
end

module ContactEmail : sig
  type t = string

  val equal : t -> t -> bool
  val pp : Format.formatter -> t -> unit
  val show : t -> t
  val value : t -> string
  val create : t -> (t, t) result
end

module EmailSuffix : sig
  (* TODO [timhub]: Hide type? *)
  type t = string

  val equal : t -> t -> bool
  val pp : Format.formatter -> t -> unit
  val show : t -> t
  val value : t -> string
  val create : t -> (t, t) result
  val schema : unit -> ('a, t) Conformist.Field.t
end

module Value : sig
  type t
end

type t

val updated_at : t -> Ptime.t
val languages : t -> Language.t list
val email_suffixes : t -> EmailSuffix.t list
val contact_email : t -> ContactEmail.t

module TermsAndConditions : sig
  type t

  val create : string -> t
  val value : t -> string
end

type event =
  | LanguagesUpdated of Language.t list
  | EmailSuffixesUpdated of EmailSuffix.t list

val handle_event : Pool_common.Database.Label.t -> event -> unit Lwt.t
val equal_event : event -> event -> bool
val pp_event : Format.formatter -> event -> unit

val find_languages
  :  Pool_common.Database.Label.t
  -> unit
  -> (t, string) Result.result Lwt.t

val find_email_suffixes
  :  Pool_common.Database.Label.t
  -> unit
  -> (t, string) Result.result Lwt.t

val find_contact_email
  :  Pool_common.Database.Label.t
  -> unit
  -> (t, string) Result.result Lwt.t

val terms_and_conditions : string Lwt.t
val last_updated : Entity.t -> Ptime.t
