open! Core

module Direction : sig
  type t =
    | Clockwise
    | Counter
  [@@deriving sexp, compare, equal, bin_io]
end

type t = {
  players : Player.t List.t;
  draw_pile : Card.t Queue.t;
  played_pile : Card.t List.t;
  current_color : Card.Color.t;
  direction : Direction.t;
  turn : Int.t;
} [@@deriving sexp, compare, equal, bin_io]

val create_card_queue : unit -> Card.t Queue.t
