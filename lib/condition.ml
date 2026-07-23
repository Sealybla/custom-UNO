open! Core

type t =
  | Always
  | MatchesTopColor
  | MatchesTopValue
  | PendingDrawsGreaterThan of int
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
  | And (c1, c2) -> eval state event c1 && eval state event c2
  | Or (c1, c2) -> eval state event c1 || eval state event c2
  | Not c -> not (eval state event c)
;;
