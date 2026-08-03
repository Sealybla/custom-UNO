open! Core

(* basically player actions but for only during the game *)
type t =
  | CardPlayed of
      { player : Player.t
      ; card : Card.t
      ; declared_color : Card.Color.t Option.t
      ; swap_with : Player.t Option.t
        (* resolved target for chosen-swap rules, validated at event
           construction (exists, not the actor) *)
      }
  | DrawRequested of { player : Player.t }
  | PassRequested of { player : Player.t }
  | UnoCalled of { player : Player.t }
[@@deriving sexp, compare, equal, bin_io]
