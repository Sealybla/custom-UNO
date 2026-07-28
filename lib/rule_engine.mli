open! Core

module Ruleset : sig
  type t = Rule.t list [@@deriving sexp, compare, equal, bin_io]

  val default : t
end

(* returns true if event holds given current rule_condition. false if doesn't
   hold *)
val eval_condition : Game_state.t -> Event.t -> Rule.Condition.t -> bool

(* changes game state and springs new events given a sequence of actions *)
val eval_action
  :  Game_state.t
  -> Rule.Action_AST.t
  -> evt:Event.t
  -> (Game_state.t * Event.t List.t) Or_error.t

(* given an event and a ruleset ,change the gamestate *)
val process_event
  :  Ruleset.t
  -> Game_state.t
  -> Event.t
  -> Game_state.t Or_error.t

val apply_action
  :  Ruleset.t
  -> Game_state.t
  -> player_id:int
  -> action:Action.Client_to_server.t
  -> Game_state.t Or_error.t
