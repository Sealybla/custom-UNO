open! Core

module Card_registry : sig
  type t = Card.t Int.Map.t [@@deriving sexp, compare, equal, bin_io]

  val of_cards : Card.t List.t -> t
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
    | ReverseDirection
    | SetStackingValue 
    | ClearStackingValue
    | AdvanceTurn
    | CheckWinner 
  [@@deriving sexp, compare, equal, bin_io]
end

type t =
  { players : Player.t list
  ; draw_pile : Card.t List.t
  ; played_pile : Card.t List.t
  ; top_card : Card.t
  ; current_color : Card.Color.t
  ; stacking_value : Card.Value.t option
  ; direction : Direction.t
  ; pending_draws : int
  ; turn : int
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
val draw_card : t -> (Card.t * t) Or_error.t
val update_player : t -> Player.t -> t
val draw_card_player : t -> int -> t Or_error.t
val update_top_card : t -> Card.t -> t
val card_of_event : Event.t -> Card.t Or_error.t
val player_of_event : Event.t -> Player.t Or_error.t

val create
  :  ?random_state:Random.State.t
  -> player_names:string List.t
  -> hand_size:int
  -> unit
  -> t Or_error.t

val apply_effect : t -> event:Event.t -> Effect.t -> t Or_error.t
