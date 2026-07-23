open! Core

module Card_registry : sig
  type t = Card.t Int.Map.t [@@deriving sexp, compare, equal, bin_io]

  val of_cards : Card.t List.t -> t
  val find : t -> int -> Card.t Or_error.t
end

module Effect : sig
  type t =
    | SetTopCard of Card.t
    | SetActiveColor of Card.Color.t
    | AddPendingDraws of int
    | ExecuteDraw of
        { player : Player.t
        ; count : int
        }
    | ReverseDirection
    | AdvanceTurn
  [@@deriving sexp, compare, equal, bin_io]
end

type t =
  { players : Player.t list
  ; draw_pile : Card.t List.t
  ; played_pile : Card.t List.t
  ; top_card : Card.t
  ; current_color : Card.Color.t
  ; direction : Direction.t
  ; turn : int
  ; card_registry : Card_registry.t
  ; winner : int option
  }
[@@deriving sexp, compare, equal, bin_io]

val create_card_deck : unit -> Card.t List.t
val shuffle : Card.t List.t -> Card.t List.t
val draw_card : t -> (Card.t * t) Or_error.t
val update_player : t -> Player.t -> t
val draw_card_player : t -> int -> t Or_error.t
val update_top_card : t -> Card.t -> t
val create : player_names:string List.t -> hand_size:int -> t Or_error.t
val apply_action :  t -> player_id:int -> action:Action.Client_to_server.t -> t Or_error.t
