open! Core

(* Rule is basically a condition with a priority and id *)
(* only used for rules *)
module Priority = struct
  type t = int [@@deriving sexp, compare, equal, bin_io]
end

module Condition = struct
  type t =
    | Always
    | MatchesTopColor
    | MatchesTopValue
    (* same printed colour AND number as the top card. Wilds never match:
       they have no printed colour, and letting one through would set the
       active colour to NoColor, which makes every card playable. *)
    | MatchesTopExactly
    | IsWildCard
    | PendingDrawsGreaterThan of int
    | IsPlayerTurn
    | IsSkip
    | IsReverse
    | IsDrawAction
    | IsPlusTwo
    | IsPlusFour
    | IsNumber of int (* the card is this number, 0-9 *)
    | IsCardColor of Card.Color.t (* the card's printed color; wilds have none *)
    | IsActionCard (* skip, reverse, +2, +4 or wild *)
    | IsNumberCard (* any 0-9, whatever its color *)
    | ActiveColorIs of Card.Color.t (* the table's color to match right now *)
    | HandSizeGreaterThan of int (* the ACTING player's hand, before the play *)
    | HandSizeEquals of int
    | TopCardIsNumber of int (* what's SHOWING on the pile, not what's played *)
    | TopCardIsAction (* the pile shows a skip/reverse/+2/+4/wild *)
    | DirectionIsClockwise
    | DrawPileLessThan of int (* endgame triggers; `draw pile is empty` = < 1 *)
    | ContinuesStack
    | StackIsOpen
    | DrewPlayableCard
    | IsPassAction
    (* the UNO button was pressed *)
    | IsUnoCall
    (* whoever pressed it is down to a single card *)
    | CallerHasUno
    (* somebody else is sitting on one card with their window still open *)
    | SomeoneElseHasUno
    | And of t * t
    | Or of t * t
    | Not of t
  [@@deriving sexp, compare, equal, bin_io]
end

type t =
  { id : int
  ; priority : Priority.t
  ; condition : Condition.t
  ; actions : Game_state.Effect.t list
    (* applied in order; the first failing effect rejects the whole action *)
  }
[@@deriving sexp, compare, equal, bin_io]
