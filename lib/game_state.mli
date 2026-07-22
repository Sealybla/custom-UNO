open! Core

module Direction : sig
  type t =
    | Clockwise
    | Counter
  [@@deriving sexp, compare, equal, bin_io]
end

(* you win function *)

(**)
type t =
  { players : Player.t list
  ; draw_pile : Card.t Queue.t (* played pile does not contain top card *)
  ; played_pile : Card.t List.t
  ; top_card : Card.t
  ; current_color : Card.Color.t
  ; direction : Direction.t
  ; turn : int
  }
[@@deriving sexp, compare, equal, bin_io]

(* val create : unit -> t *)
val draw_card_player : t -> int -> unit Or_error.t
val draw_card_player_exn : t -> int -> unit
val start_distribution : t -> int -> int -> t
