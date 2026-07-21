open! Core

type t

(*adding/playing cards from hand, player implements all actions*)

val create: int -> string -> int -> t

val get_hand: t -> (Int.t, unit) Hashtbl.t

val add_card: t -> int -> unit