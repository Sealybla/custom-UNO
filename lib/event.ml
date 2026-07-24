open! Core
open Or_error.Let_syntax

(* basically player actions but for only during the game *)
type t =
  | CardPlayed of
      { player : Player.t
      ; card : Card.t
      ; declared_color : Card.Color.t Option.t
      }
  | DrawRequested of { player : Player.t }
[@@deriving sexp, compare, equal, bin_io]

(* Convert network wire format into engine event format *)
let of_client_action
  (state : Game_state.t)
  ~player
  ~(action : Action.Client_to_server.t)
  : t Or_error.t
  =
  match action with
  | Play { card_id; declared_color } ->
    let%map card =
      Game_state.Card_registry.find state.card_registry card_id
    in
    CardPlayed { player; card; declared_color }
  | Draw -> Ok (DrawRequested { player })
  | Join_lobby _ | Quit ->
    Or_error.error_s
      [%message "Non-gameplay action" (action : Action.Client_to_server.t)]
;;
