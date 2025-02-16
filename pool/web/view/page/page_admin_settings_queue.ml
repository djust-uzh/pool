open Tyxml.Html
module HttpUtils = Http_utils

let formatted_date_time = Pool_common.Utils.Time.formatted_date_time

let data_table Pool_context.{ language; _ } (queued_jobs, query) =
  let open Pool_common in
  let open Queue in
  let url = Uri.of_string "/admin/settings/queue" in
  let data_table =
    Component.DataTable.create_meta
      ?filter:filterable_by
      ~search:searchable_by
      url
      query
      language
  in
  let cols =
    let field_to_string field =
      Utils.field_to_string_capitalized language field |> txt
    in
    [ `column column_job_name
    ; `column column_job_status
    ; `custom (field_to_string Message.Field.Input)
    ; `custom (field_to_string Message.Field.LastError)
    ; `column column_last_error_at
    ; `column column_next_run
    ; `empty
    ]
  in
  let th_class = [ "w-1"; "w-1"; "w-4"; "w-2"; "w-1"; "w-1" ] in
  let row
    { Sihl_queue.id
    ; name
    ; status
    ; input
    ; last_error
    ; last_error_at
    ; next_run_at
    ; _
    }
    =
    let formatted_date_time date =
      span ~a:[ a_class [ "nobr" ] ] [ txt (formatted_date_time date) ]
    in
    [ txt name
    ; txt (Status.sihl_queue_to_human status)
    ; span ~a:[ a_class [ "word-break-all" ] ] [ txt (CCString.take 80 input) ]
    ; txt (CCOption.value ~default:"-" last_error)
    ; last_error_at |> CCOption.map_or ~default:(txt "-") formatted_date_time
    ; next_run_at |> formatted_date_time
    ; Format.asprintf "/admin/settings/queue/%s" id
      |> Component.Input.link_as_button ~icon:Component.Icon.Eye
    ]
    |> CCList.map CCFun.(CCList.return %> td)
    |> tr
  in
  Component.DataTable.make
    ~target_id:"queue-ob-list"
    ~th_class
    ~cols
    ~row
    data_table
    queued_jobs
;;

let job_detail
  language
  { Sihl_queue.name
  ; input
  ; tries
  ; next_run_at
  ; max_tries
  ; status
  ; last_error
  ; last_error_at
  ; tag
  ; _
  }
  =
  let default = "-" in
  let vertical_table =
    Component.Table.vertical_table
      ~classnames:[ "layout-fixed" ]
      ~align_top:true
      `Striped
      language
  in
  let job_detail =
    let open Pool_common.Message in
    [ Field.Name, name |> txt
    ; ( Field.Input
      , input
        |> Yojson.Safe.from_string
        |> Yojson.Safe.pretty_to_string
        |> HttpUtils.add_line_breaks )
    ; Field.Tag, tag |> CCOption.value ~default |> txt
    ; Field.Tries, tries |> CCInt.to_string |> txt
    ; Field.MaxTries, max_tries |> CCInt.to_string |> txt
    ; Field.Status, status |> Sihl.Contract.Queue.show_instance_status |> txt
    ; ( Field.LastErrorAt
      , last_error_at |> CCOption.map_or ~default formatted_date_time |> txt )
    ; Field.LastError, last_error |> CCOption.value ~default |> txt
    ; Field.NextRunAt, next_run_at |> formatted_date_time |> txt
    ]
    |> vertical_table
  in
  div [ job_detail ]
;;

let layout language children =
  div
    ~a:[ a_class [ "trim"; "safety-margin" ] ]
    [ h1
        ~a:[ a_class [ "heading-1" ] ]
        [ txt Pool_common.(Utils.nav_link_to_string language I18n.Queue) ]
    ; children
    ]
;;

let index (Pool_context.{ language; _ } as context) job =
  data_table context job |> layout language
;;

let detail Pool_context.{ language; _ } job =
  job_detail language job |> layout language
;;
