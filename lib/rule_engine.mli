open! Core

module Ruleset : sig
  type t = Rule.t list [@@deriving sexp, compare, equal, bin_io]

  val default : t
  val draw_until_variant : t
  val stacking_variant : t

  (* stacking play rules with draw-until drawing *)
  val stacking_draw_until_variant : t

  (* true if any rule in the set can open a same-value stack *)
  val uses_stacking : t -> bool
end


val event_of_client_action
  :  Game_state.t
  -> player:Player.t
  -> action:Action.Client_to_server.t
  -> Event.t Or_error.t


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

(* true if some rule would accept a Pass from the current player right now
   (drives the UI's pass-button visibility) *)
val pass_available : Ruleset.t -> Game_state.t -> bool

val apply_action
  :  Ruleset.t
  -> Game_state.t
  -> player_id:int
  -> action:Action.Client_to_server.t
  -> Game_state.t Or_error.t

(* true when a pass is the current player's only legal move (no card play
   and no draw would be accepted) - the server then passes for them *)
val only_pass_available : Ruleset.t -> Game_state.t -> bool
