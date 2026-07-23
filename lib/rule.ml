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
    | PendingDrawsGreaterThan of int
    | IsPlayerTurn
    | And of t * t
    | Or of t * t
    | Not of t
  [@@deriving sexp, compare, equal, bin_io]

  (* True if event can be played in current game state given the condition
     tree, False if event cannot be played in current game state given
     condition tree *)
  let rec eval (state : Game_state.t) (event : Event.t) (cond : t) : bool =
    match cond with
    | Always -> true
    | MatchesTopColor -> true
    | MatchesTopValue -> true
    | PendingDrawsGreaterThan _ -> true
    | IsPlayerTurn -> true
    | And (c1, c2) -> eval state event c1 && eval state event c2
    | Or (c1, c2) -> eval state event c1 || eval state event c2
    | Not c -> not (eval state event c)
  ;;
end

module Action_AST = struct
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
