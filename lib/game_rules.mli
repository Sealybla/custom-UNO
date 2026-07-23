open! Core

(** determines if a card can legally be placed onto the discard pile based on
    official Uno rules. *)
val is_valid_play
  :  top_card:Card.t
  -> played_card:Card.t
  -> current_color:Card.Color.t
  -> bool

(** returns how many cards a player must draw if an effect card is played
    (e.g., Plus returns 2, Wild4 returns 4). *)
val calculate_draw_penalty : Card.Value.t -> int

(* calculates the next active turn index based on card side effects *)
val get_next_turn
  :  current_turn:int
  -> player_count:int
  -> direction:Direction.t
  -> effect:Card.Value.t
  -> int

val get_next_direction :  player_count:int -> direction:Direction.t -> effect:Card.Value.t -> Direction.t


