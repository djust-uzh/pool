module RepoEntity = Repo_entity
module Database = Pool_database
module Dynparam = Utils.Database.Dynparam

module Sql = struct
  let sql_select_columns =
    (Entity.Id.sql_select_fragment ~field:"pool_waiting_list.uuid"
     :: Contact.Repo.sql_select_columns)
    @ Experiment.Repo.sql_select_columns
    @ [ "pool_waiting_list.comment"
      ; "pool_waiting_list.created_at"
      ; "pool_waiting_list.updated_at"
      ]
  ;;

  let joins =
    Format.asprintf
      {sql|
        LEFT JOIN pool_contacts
          ON pool_waiting_list.contact_uuid = pool_contacts.user_uuid
        %s
        LEFT JOIN pool_experiments
          ON pool_waiting_list.experiment_uuid = pool_experiments.uuid
        %s
      |sql}
      Contact.Repo.joins
      Experiment.Repo.joins
  ;;

  let find_request_sql ?(count = false) where_fragment =
    let columns =
      if count then "COUNT(*)" else CCString.concat ", " sql_select_columns
    in
    Format.asprintf
      {sql|SELECT %s FROM pool_waiting_list %s %s|sql}
      columns
      joins
      where_fragment
  ;;

  let find_request =
    let open Caqti_request.Infix in
    {sql|
      WHERE pool_waiting_list.uuid = UNHEX(REPLACE(?, '-', ''))
    |sql}
    |> find_request_sql
    |> Caqti_type.string ->! RepoEntity.t
  ;;

  let find pool id =
    let open Utils.Lwt_result.Infix in
    Utils.Database.find_opt
      (Pool_database.Label.value pool)
      find_request
      (id |> Pool_common.Id.value)
    ||> CCOption.to_result Pool_common.Message.(NotFound Field.WaitingList)
  ;;

  let user_is_enlisted_request =
    let open Caqti_request.Infix in
    {sql|
      WHERE
        contact_uuid = UNHEX(REPLACE($1, '-', ''))
      AND
        experiment_uuid = UNHEX(REPLACE($2, '-', ''))
    |sql}
    |> find_request_sql
    |> Caqti_type.(t2 string string) ->! RepoEntity.t
  ;;

  let find_by_contact_and_experiment pool contact experiment_id =
    Utils.Database.find_opt
      (Pool_database.Label.value pool)
      user_is_enlisted_request
      ( contact |> Contact.id |> Pool_common.Id.value
      , experiment_id |> Experiment.Id.value )
  ;;

  let find_by_experiment ?query pool id =
    let where =
      let sql =
        {sql|
          pool_waiting_list.experiment_uuid = UNHEX(REPLACE(?, '-', ''))
          AND NOT EXISTS (
            SELECT 1
            FROM pool_assignments
            INNER JOIN pool_sessions ON pool_assignments.session_uuid = pool_sessions.uuid
              AND pool_sessions.experiment_uuid = UNHEX(REPLACE(?, '-', ''))
            WHERE pool_assignments.contact_uuid = user_users.uuid
              AND pool_assignments.marked_as_deleted != 1)
        |sql}
      in
      let dyn =
        let open Experiment in
        Dynparam.(
          empty
          |> add Pool_common.Repo.Id.t (Id.to_common id)
          |> add Pool_common.Repo.Id.t (Id.to_common id))
      in
      sql, dyn
    in
    Query.collect_and_count
      pool
      query
      ~select:find_request_sql
      ~where
      RepoEntity.t
  ;;

  let find_binary_experiment_id_sql =
    {sql|
      SELECT exp.uuid
      FROM pool_waiting_list AS wl
      LEFT JOIN pool_experiments AS exp ON wl.experiment_uuid = exp.uuid
      WHERE wl.uuid = ?
    |sql}
  ;;

  let find_experiment_id_request =
    let open Caqti_request.Infix in
    {sql|
      SELECT
        LOWER(CONCAT(
          SUBSTR(HEX(pool_waiting_list.experiment_uuid), 1, 8), '-',
          SUBSTR(HEX(pool_waiting_list.experiment_uuid), 9, 4), '-',
          SUBSTR(HEX(pool_waiting_list.experiment_uuid), 13, 4), '-',
          SUBSTR(HEX(pool_waiting_list.experiment_uuid), 17, 4), '-',
          SUBSTR(HEX(pool_waiting_list.experiment_uuid), 21)
        ))
      FROM pool_waiting_list
      WHERE pool_waiting_list.uuid = UNHEX(REPLACE(?, '-', ''))
    |sql}
    |> Pool_common.Repo.Id.t ->! Experiment.Repo.Entity.Id.t
  ;;

  let find_experiment_id pool id =
    let open Utils.Lwt_result.Infix in
    Utils.Database.find_opt
      (Pool_database.Label.value pool)
      find_experiment_id_request
      id
    ||> CCOption.to_result Pool_common.Message.(NotFound Field.Experiment)
  ;;

  let insert_request =
    let open Caqti_request.Infix in
    {sql|
      INSERT INTO pool_waiting_list (
        uuid,
        contact_uuid,
        experiment_uuid,
        comment
      ) VALUES (
        UNHEX(REPLACE($1, '-', '')),
        UNHEX(REPLACE($2, '-', '')),
        UNHEX(REPLACE($3, '-', '')),
        $4
      )
    |sql}
    |> Caqti_type.(RepoEntity.Write.t ->. unit)
  ;;

  let insert pool =
    Utils.Database.exec (Pool_database.Label.value pool) insert_request
  ;;

  let update_request =
    let open Caqti_request.Infix in
    {sql|
      UPDATE pool_waiting_list
        SET
          comment = $1
        WHERE uuid = UNHEX(REPLACE($2, '-', ''))
    |sql}
    |> Caqti_type.(t2 (option string) string ->. unit)
  ;;

  let update pool (m : Entity.t) =
    let open Entity in
    let caqti =
      m.admin_comment |> AdminComment.value, m.id |> Pool_common.Id.value
    in
    Utils.Database.exec (Pool_database.Label.value pool) update_request caqti
  ;;

  let delete_request =
    let open Caqti_request.Infix in
    {sql|
      DELETE FROM pool_waiting_list
      WHERE
        uuid = UNHEX(REPLACE($1, '-', ''))
    |sql}
    |> Caqti_type.(string ->. unit)
  ;;

  let delete pool m =
    Utils.Database.exec
      (Database.Label.value pool)
      delete_request
      (m.Entity.id |> Pool_common.Id.value)
  ;;
end

let find = Sql.find
let find_by_contact_and_experiment = Sql.find_by_contact_and_experiment

let user_is_enlisted pool contact experiment_id =
  let open Utils.Lwt_result.Infix in
  Sql.find_by_contact_and_experiment pool contact experiment_id
  ||> CCOption.is_some
;;

let find_by_experiment = Sql.find_by_experiment
let find_experiment_id = Sql.find_experiment_id
let insert = Sql.insert
let update = Sql.update
let delete = Sql.delete
