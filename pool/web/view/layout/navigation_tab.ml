open CCFun
open Entity
open Tyxml.Html

let make_tabs html links =
  let toggle_id = "tab-nav-toggle" in
  let nav =
    CCList.map
      (fun (label, url, active) ->
        match active, url with
        | true, _ | false, None ->
          span ~a:[ a_class [ "active" ] ] [ txt label ]
        | _, Some url ->
          a ~a:[ a_href (Sihl.Web.externalize_path url) ] [ txt label ])
      links
    |> fun links ->
    div
      ~a:[ a_class [ "tab-nav-container" ] ]
      [ div
          ~a:[ a_class [ "tab-nav-header" ] ]
          [ label
              ~a:[ a_class [ "icon-lg" ]; a_label_for toggle_id ]
              Component.Icon.[ to_html MenuOutline ]
          ]
      ; input
          ~a:[ a_input_type `Checkbox; a_class [ "toggle" ]; a_id toggle_id ]
          ()
      ; nav
          ~a:[ a_class [ "tab-nav"; "toggle-body"; "flexrow"; "flex-gap" ] ]
          links
      ]
  in
  div [ nav; div ~a:[ a_class [ "tab-body" ] ] html ]
;;

let create ?active_navigation language links html =
  let open Pool_common in
  CCList.map
    (fun { NavElement.label; url; _ } ->
      let is_active =
        active_navigation
        |> CCOption.map_or ~default:false (flip I18n.equal_nav_link label)
      in
      let label = Utils.nav_link_to_string language label in
      label, url, is_active)
    links
  |> make_tabs html
;;
