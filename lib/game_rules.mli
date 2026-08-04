open! Core

(** does this card satisfy the colour in force? An undeclared colour
    (NoColor, i.e. the game opened on a flipped wild) accepts anything. *)
val matches_color : played_card:Card.t -> current_color:Card.Color.t -> bool

(** determines if a card can legally be placed onto the discard pile based on
    official Uno rules. *)
val is_valid_play
  :  top_card:Card.t
  -> played_card:Card.t
  -> current_color:Card.Color.t
  -> bool

val choose_card
  :  hand:Card.t list
  -> top_card:Card.t
  -> current_color:Card.Color.t
  -> Card.t option
