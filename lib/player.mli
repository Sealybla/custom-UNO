open! Core

type t =
  { id : int
  ; name : string
  ; hand : Int.t List.t
  }
[@@deriving sexp, compare, equal, bin_io]

(* adding/playing cards from hand, player implements all actions *)

val create : int -> string -> t
val get_hand : t -> Int.t List.t
val add_card : t -> int -> t
val get_id : t -> int
val get_name : t -> string
val remove_card : t -> int -> t Or_error.t