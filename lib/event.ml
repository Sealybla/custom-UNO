open! Core
open Or_error.Let_syntax

(* basically player actions but for only during the game *)
type t =
  | CardPlayed of
      { player : Player.t
      ; card : Card.t
      ; declared_color : Card.Color.t Option.t
      }
  | DrawRequested of { player : Player.t }
  | PassRequested of { player : Player.t }
[@@deriving sexp, compare, equal, bin_io]

