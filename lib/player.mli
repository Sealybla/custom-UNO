open! Core

type t =
  { id : int
  ; name : string
  ; mutable hand : Int.t List.t
  }
[@@deriving sexp, compare, equal, bin_io]

(* adding/playing cards from hand, player implements all actions *)

val create : int -> string -> int -> t
val get_hand : t -> Int.t List.t
val add_card : t -> int -> unit
