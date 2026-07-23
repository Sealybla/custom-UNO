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
    | PendingDrawsGreaterThan of int
    | IsPlayerTurn
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
