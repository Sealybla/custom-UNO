open! Core

(* Actions sent from a player's client to the central server *)
module Client_to_server = struct
  type t =
    | Join_lobby of { player_name : String.t }
    | Play of { card_id : Int.t;
                declared_color : Card.Color.t Option.t }
    | Draw
    | Quit
  [@@deriving sexp, compare, equal, bin_io]
end

(* Updates sent from the server to update the local Bonsai UI *)
module Server_to_client = struct
  type t =
    | Lobby_updated of { players : String.t List.t }
    | Game_started of { your_hand : Card.t List.t;
                        top_card : Card.t; 
                        current_color : Card.Color.t;
                        player_names : String.t List.t;
                        current_player_name : String.t }
    | Hand_updated of { your_hand : Card.t List.t }
    | Pile_updated of
        { top_card : Card.t
        ; current_color : Card.Color.t
        }
    | Turn_changed of { current_player_name : String.t }
    | Hand_counts of { counts : (String.t * Int.t) List.t }
    | Game_over of { winner_name : String.t }
  [@@deriving sexp, compare, equal, bin_io]
end
