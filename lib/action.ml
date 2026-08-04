open! Core

(* Actions sent from a player's client to the central server *)
module Client_to_server = struct
  type t =
    | Play of
        { card_id : Int.t
        ; declared_color : Card.Color.t Option.t
        ; swap_with : String.t Option.t
          (* target for chosen-swap rules; ignored by rules that don't swap *)
        }
    | Draw
    | Pass
    | Call_uno
  [@@deriving sexp, compare, equal, bin_io]
end

(* Updates sent from the server to update the local Bonsai UI *)
module Server_to_client = struct
  type t =
    | Lobby_updated of
        { players : String.t List.t
        ; ready_players : String.t List.t (* subset of players who clicked ready *)
        ; last_winner : String.t Option.t (* winner of this room's last game *)
        }
    | Game_started of { your_hand : Card.t List.t;
                        top_card : Card.t;
                        current_color : Card.Color.t;
                        player_names : String.t List.t;
                        current_player_name : String.t;
                        pending_draws : Int.t;
                        stacking_enabled : Bool.t }
    (* [playable_ids] is what the engine would accept from this player right
       now, including out-of-turn jump-ins; the UI highlights exactly these
       rather than second-guessing the ruleset *)
    | Hand_updated of
        { your_hand : Card.t List.t
        ; playable_ids : Int.t List.t
        ; swap_target_ids : Int.t List.t
          (* subset of [playable_ids] that additionally needs a swap
             target declared - the UI asks with a player picker *)
        }
    | Pile_updated of
        { top_card : Card.t
        ; current_color : Card.Color.t
        ; pending_draws : Int.t
        }
    | Turn_changed of
        { current_player_name : String.t
        ; can_pass : Bool.t (* a Pass by the current player would be legal *)
        ; stack_value : Card.Value.t Option.t (* open stack's value, if any *)
        ; uno_race : Bool.t
          (* an UNO catch window is open somewhere: the button is live for
             EVERYONE (save yourself or catch them) until somebody presses
             it or the next action closes the window *)
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
    (* the current player is running out of turn time; at zero the server
       plays for them *)
    | Turn_countdown of { player_name : String.t; seconds : Int.t }
    | Rules_updated of
        { player_name : String.t
        ; num_rules : Int.t
        ; rules_text : String.t (* the submitted text, so every editor can sync *)
        }
    | Action_rejected of { reason : String.t }
    (* pure-notification events driving the table animations *)
    | Player_skipped of { player_name : String.t }
    | Forced_draw of { player_name : String.t; count : Int.t }
    | Direction_changed of { direction : Direction.t }
    (* entire hands changed owners (seven-zero style rules): (from, to)
       name pairs. Two reciprocal moves are a swap, one per player a rotate *)
    | Hands_moved of { moves : (String.t * String.t) List.t }
    (* an accepted out-of-turn play: this player grabbed the turn *)
    | Jumped_in of { player_name : String.t }
  [@@deriving sexp, compare, equal, bin_io]
end
