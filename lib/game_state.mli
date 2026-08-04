open! Core

module Card_registry : sig
  type t = Card.t Int.Map.t [@@deriving sexp, compare, equal, bin_io]

  val find : t -> int -> Card.t Or_error.t
end

module Effect : sig
  type t =
    | PlayTriggeringCard
    | SetActiveColor of Card.Color.t
    | SetColorFromTriggeringCard
    | SetDeclaredColor
    | AddPendingDraws of int
    | ApplyPendingDraws
    | ExecuteDraw of int
    | DrawForNextPlayer of int
    | DrawUntilPlayable
    | DrawAndDecide
    | ReverseDirection
    | SetStackingValue
    | ClearStackingValue
    | AdvanceTurn
    | JumpToActor
    | CheckWinner
    | MarkUnoCalled
    | PenalizeUnoCaller of int
    | PenalizeUnoTarget of int
    | SwapHandsWithNext
    | SwapHandsWithChosen
    | RotateHands
    | AllOthersDraw of int
    | ChosenPlayerDraws of int (* the aimed-at player draws (targeted +4) *)
    | Reject of string (* fail the whole action with this message *)
  [@@deriving sexp, compare, equal, bin_io]
end

(* the rejection text the chosen-target effects (SwapHandsWithChosen,
   ChosenPlayerDraws) produce when the play declared no target. The server
   greps for it when simulating playability, turning "would be legal, but
   needs a target" into the UI's player picker. *)
val target_needed : string

type t =
  { players : Player.t list
  ; draw_pile : Card.t List.t
  ; played_pile : Card.t List.t
  ; top_card : Card.t
  ; current_color : Card.Color.t
  ; stacking_value : Card.Value.t option
  ; direction : Direction.t
  ; pending_draws : int
  ; drew_playable : bool
  ; turns_advanced : int
  ; turn : int
  ; uno_vulnerable : int option
  ; card_registry : Card_registry.t
  ; winner : int option
  }
[@@deriving sexp, compare, equal, bin_io]

val for_testing
  :  player_hands:(string * Card.t List.t) List.t
  -> top_card:Card.t
  -> draw_pile:Card.t List.t
  -> pending_draws:int
  -> turn:int
  -> t

val create_card_deck : unit -> Card.t List.t
val shuffle : ?random_state:Random.State.t -> Card.t List.t -> Card.t List.t

val create
  :  ?random_state:Random.State.t
  -> player_names:string List.t
  -> hand_size:int
  -> unit
  -> t Or_error.t

val hand_size : t -> int -> int
val apply_effect : t -> event:Event.t -> Effect.t -> t Or_error.t

(* recomputes who can be caught for not calling UNO; called once per action
   by Rule_engine.apply_action, never from a rule *)
val update_uno_window : t -> actor_id:int -> event:Event.t -> t

(* Which ENTIRE hands changed owners across one action, as (from, to)
   player-index pairs: [to]'s whole hand after the action is [from]'s hand
   from before it (minus the card the actor just [played], for the hand the
   actor traded away). A swap reports two moves, a rotate one per player.
   Ordinary plays and draws never look like a move - drawn cards come from
   the pile, so a grown hand can't equal anyone's old hand. Drives the
   swap/rotate animations and keeps the forced-draw notification from
   misreading a received hand as a penalty. Empty hands are skipped: there
   is nothing to animate and empty sets would match each other. *)
val hand_moves : before:t -> after:t -> played:Int.t Option.t -> (int * int) list
