open! Core

(* basically player actions but for only during the game *)
type t =
  | CardPlayed of
      { player : Player.t
      ; card_id : int
      ; declared_color : Card.Color.t Option.t
      }
  | DrawRequested of { player : Player.t }
[@@deriving sexp, compare, equal, bin_io]
