let create_participant_table =
  Sihl.Database.Migration.create_step
    ~label:"create participant table"
    {sql|
      CREATE TABLE IF NOT EXISTS pool_participants (
        `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
        `user_uuid` binary(16) NOT NULL,
        `recruitment_channel` varchar(128) NOT NULL,
        `terms_accepted_at` timestamp NULL,
        `paused` boolean NOT NULL,
        `disabled` boolean NOT NULL,
        `verified` timestamp NULL,
        `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      UNIQUE KEY `unique_uuid` (`user_uuid`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    |sql}
;;

let add_changeset_version =
  Sihl.Database.Migration.create_step
    ~label:"add changeset version columns for participants"
    {sql|
     ALTER TABLE pool_participants
     ADD COLUMN firstname_version bigint(20) NOT NULL DEFAULT 0 AFTER verified,
     ADD COLUMN lastname_version bigint(20) NOT NULL DEFAULT 0 AFTER firstname_version,
     ADD COLUMN paused_version bigint(20) NOT NULL DEFAULT 0 AFTER lastname_version;
    |sql}
;;

let migration () =
  Sihl.Database.Migration.(
    empty "participant"
    |> add_step create_participant_table
    |> add_step add_changeset_version)
;;
