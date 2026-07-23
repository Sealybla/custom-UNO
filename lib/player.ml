open! Core

type t =
  { id : int
  ; name : string
  ; hand : Int.t List.t
  }
[@@deriving sexp, compare, equal, bin_io]

let create id name = { id; name; hand = [] }
let get_hand t = t.hand
let add_card t card_id = {t with hand = card_id :: t.hand}
let get_id t = t.id

let get_name t = t.name

let remove_card t card_id =
  match List.split_while t.hand ~f:(fun c -> not (Int.equal c card_id)) with
  | _, [] -> Or_error.error_s [%message "Card not in hand" (card_id : int)]
  | before, _ :: after -> Ok { t with hand = before @ after }
;;