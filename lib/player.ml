open! Core

type t =
  { id : int
  ; name : string
  ; mutable hand : Int.t List.t
  }
[@@deriving sexp, compare, equal, bin_io]

let create id name max_hand_size = { id; name; hand = [] }
let get_hand t = t.hand
let add_card t card_id = t.hand <- card_id :: t.hand
