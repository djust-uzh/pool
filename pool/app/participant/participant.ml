include Entity
include Event

let login _ ~email:_ ~password:_ = Utils.todo ()
let find = Repo.find
let insert = Repo.insert

let find_by_user pool (user : Sihl_user.t) =
  user.Sihl_user.id |> Pool_common.Id.of_string |> Repo.find pool
;;

let find_duplicates = Utils.todo
let has_terms_accepted = Event.has_terms_accepted
