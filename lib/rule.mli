open! Core

(* Rule is basically a condition with a priority and id *)
(* only used for rules *)
module Priority : sig
  type t = int [@@deriving sexp, compare, equal, bin_io]
end

module Condition : sig
  type t =
    | Always
    | MatchesTopColor
    | MatchesTopValue
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
    | ActiveColorIs of Card.Color.t (* the table's color to match right now *)
    | ContinuesStack
    | StackIsOpen
    | DrewPlayableCard
    | IsPassAction
    | IsUnoCall
    | CallerHasUno
    | SomeoneElseHasUno
    | And of t * t
    | Or of t * t
    | Not of t
  [@@deriving sexp, compare, equal, bin_io]
end

module Action_AST : sig
  type t =
    | Mutate of Game_state.Effect.t
    | Chain_event of Event.t
    | Sequence of t list
  [@@deriving sexp, compare, equal, bin_io]
end

type t =
  { id : int
  ; priority : Priority.t
  ; condition : Condition.t
  ; actions : Action_AST.t list
  }
[@@deriving sexp, compare, equal, bin_io]
