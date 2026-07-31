open! Core

(* Actions sent from a player's client to the central server *)
module Client_to_server = struct
  type t =
    | Join_lobby of { player_name : String.t }
    | Play of { card_id : Int.t;
                declared_color : Card.Color.t Option.t }
    | Draw
    | Pass
    | Call_uno
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
                        current_player_name : String.t;
                        pending_draws : Int.t;
                        stacking_enabled : Bool.t }
    | Hand_updated of { your_hand : Card.t List.t }
    | Pile_updated of
        { top_card : Card.t
        ; current_color : Card.Color.t
        ; pending_draws : Int.t
        }
    | Turn_changed of
        { current_player_name : String.t
        ; can_pass : Bool.t (* a Pass by the current player would be legal *)
        ; stack_value : Card.Value.t Option.t (* open stack's value, if any *)
        }
    | Hand_counts of { counts : (String.t * Int.t) List.t }
    | Game_over of { winner_name : String.t }
    (* a player successfully claimed UNO (or caught somebody who didn't) *)
    | Uno_called of { player_name : String.t }
    (* a bad UNO press: either they were caught holding one card, or they
       called with nothing to call. [caught] distinguishes the two. *)
    | Uno_penalty of
        { player_name : String.t
        ; count : Int.t
        ; caught : Bool.t
        }
    | Rules_updated of { player_name : String.t; num_rules : Int.t }
    | Action_rejected of { reason : String.t }
    (* pure-notification events driving the table animations *)
    | Player_skipped of { player_name : String.t }
    | Forced_draw of { player_name : String.t; count : Int.t }
    | Direction_changed of { direction : Direction.t }
  [@@deriving sexp, compare, equal, bin_io]
end
