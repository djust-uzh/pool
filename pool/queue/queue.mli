module JobName : sig
  type t =
    | SendEmail
    | SendTextMessage

  val pp : Format.formatter -> t -> unit
  val show : t -> string
  val sexp_of_t : t -> Ppx_sexp_conv_lib.Sexp.t
  val t_of_yojson : Yojson.Safe.t -> t
  val yojson_of_t : t -> Yojson.Safe.t
  val equal : t -> t -> bool
end

module Status : sig
  type t =
    | Pending
    | Succeeded
    | Failed
    | Cancelled

  val pp : Format.formatter -> t -> unit
  val show : t -> string
  val sexp_of_t : t -> Ppx_sexp_conv_lib.Sexp.t
  val t_of_yojson : Yojson.Safe.t -> t
  val yojson_of_t : t -> Yojson.Safe.t
  val equal : t -> t -> bool
  val sihl_queue_to_human : Sihl.Contract.Queue.instance_status -> string
end

val hide : 'a Sihl.Contract.Queue.job -> Sihl.Contract.Queue.job'
val lifecycle : Sihl.Container.lifecycle

val register
  :  ?jobs:Sihl.Contract.Queue.job' list
  -> unit
  -> Sihl.Container.Service.t

val find
  :  Pool_database.Label.t
  -> Pool_common.Id.t
  -> (Sihl_queue.instance, Pool_common.Message.error) Lwt_result.t

val find_by
  :  ?query:Query.t
  -> Pool_database.Label.t
  -> (Sihl_queue.instance list * Query.t) Lwt.t

val count_workable
  :  Pool_database.Label.t
  -> (int, Pool_common.Message.error) Lwt_result.t

val column_job_name : Query.Column.t
val column_job_status : Query.Column.t
val column_last_error : Query.Column.t
val column_last_error_at : Query.Column.t
val column_next_run : Query.Column.t
val default_query : Query.t
val filterable_by : Query.Filter.human option
val searchable_by : Query.Column.t list
val sortable_by : Query.Column.t list

module Guard : sig
  module Access : sig
    val index : Guard.ValidationSet.t
    val read : Guard.ValidationSet.t
  end
end
