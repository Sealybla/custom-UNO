open! Core

module Client_to_server : sig
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

module Server_to_client : sig
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
        ; can_pass : Bool.t
        ; stack_value : Card.Value.t Option.t
        ; uno_race : Bool.t
          (* an UNO catch window is open somewhere: the button is live for
             EVERYONE (save yourself or catch them) until somebody presses
             it or the next action closes the window *)
        }
    | Hand_counts of { counts : (String.t * Int.t) List.t }
    | Game_over of
        { winner_name : String.t
        ; standings : String.t List.t
        }
    | Player_finished of
        { player_name : String.t
        ; place : Int.t
        }
    | Uno_called of { player_name : String.t }
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
