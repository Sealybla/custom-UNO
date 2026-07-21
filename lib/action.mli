open! Core

module Client_to_server : sig
  type t =
    | Join_lobby of { player_name : String.t }
    | Start_game
    | Play of Card.t
    | Choose of Card.Color.t
    | Draw
    | Uno
    | Quit
  [@@deriving sexp, compare, equal, bin_io]
end

module Server_to_client : sig
  type t =
    | Lobby_updated of { players : String.t List.t }
    | Game_started of { initial_state : Game_state.t }
    | Hand_updated of { your_hand : Card.t List.t }
    | Pile_updated of
        { top_card : Card.t
        ; current_color : Card.Color.t
        }
    | Turn_changed of { current_player_name : String.t }
    | Game_over of { winner_name : String.t }
  [@@deriving sexp, compare, equal, bin_io]
end
