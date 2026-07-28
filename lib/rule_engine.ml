open! Core
open Or_error.Let_syntax

module Ruleset = struct
  type t = Rule.t list [@@deriving sexp, compare, equal, bin_io]

  let default : t =
    [ (* play matching color *)
      { id = 1
      ; priority = 1
      ; condition = And (MatchesTopColor, IsPlayerTurn)
      ; actions = [ PlayCard ]
      }
    ; (* draw when forced *)
      { id = 2
      ; priority = 4
      ; condition =
          And (And (Not MatchesTopColor, Not MatchesTopValue), IsPlayerTurn)
      ; actions = [ ExecuteDraw ]
      }
    ]
  ;;
end

let rec eval_condition
  (state : Game_state.t)
  (evt : Event.t)
  (cond : Rule.Condition.t)
  : bool
  =
  match cond with
  | Always -> true
  | MatchesTopColor ->
    (match evt with
     | CardPlayed { card; _ } ->
       Card.Color.equal (Card.get_color card) state.current_color
       || Card.Color.equal (Card.get_color card) NoColor
     | _ -> false)
  | MatchesTopValue ->
    (match evt with
     | CardPlayed { card; _ } ->
       Card.Value.equal (Card.get_value card) (Card.get_value state.top_card)
     | _ -> false)
  | IsWildCard ->
    (match evt with
     | CardPlayed { card; _ } ->
       (match Card.get_value card with Wild | Wild4 -> true | _ -> false)
     | _ -> false)
  | PendingDrawsGreaterThan n -> state.pending_draws > n
  | IsPlayerTurn -> true
  | And (c1, c2) ->
    eval_condition state evt c1 && eval_condition state evt c2
  | Or (c1, c2) -> eval_condition state evt c1 || eval_condition state evt c2
  | Not c -> not (eval_condition state evt c)
;;

let rec eval_action
  (state : Game_state.t)
  (act : Rule.Action_AST.t)
  ~(evt : Event.t)
  : (Game_state.t * Event.t list) Or_error.t
  =
  match act with
  | Mutate eff ->
    (* apply effect implemented soon *)
    let%map next_state = Game_state.apply_effect state eff in
    next_state, []
  | Chain_event evt -> Ok (state, [ evt ])
  | Sequence actions ->
    List.fold_result
      actions
      ~init:(state, [])
      ~f:(fun (curr_state, curr_evts) a ->
        let%map next_state, new_evts = eval_action curr_state ~evt a in
        next_state, curr_evts @ new_evts)
  | PlayCard ->
    (match evt with
     | CardPlayed { player; card; declared_color } ->
       (match Game_state.play_card state card player with
        | Ok new_state -> Ok (new_state, [])
        | _ -> Or_error.error_s [%message "Card played did NOT work"])
     | _ -> Or_error.error_s [%message "must be card played"])
  | ExecuteDraw ->
    (match evt with
     | DrawRequested { player } ->
       (match Game_state.draw_card_player state (Player.get_id player) with
        | Ok new_state -> Ok (new_state, [])
        | _ -> Or_error.error_s [%message "Draw requested did NOT work"])
     | _ -> Or_error.error_s [%message "must be draw requested played"])
;;

let rec process_event
  (rules : Ruleset.t)
  (state : Game_state.t)
  (evt : Event.t)
  : Game_state.t Or_error.t
  =
  let%bind () =
    match state.winner with
    | Some w -> Or_error.error_s [%message "Game is over" ~winner:(w : int)]
    | None -> Ok ()
  in
  let sorted_rules =
    List.sort rules ~compare:(fun r1 r2 ->
      Int.compare r2.priority r1.priority)
  in
  let matching_rules =
    List.filter sorted_rules ~f:(fun rule ->
      eval_condition state evt rule.condition)
  in
  match List.is_empty matching_rules with
  | true ->
    Or_error.error_s
      [%message "Illegal move: no matching rules" (evt : Event.t)]
  | false ->
    let actions = List.concat_map matching_rules ~f:(fun r -> r.actions) in
    List.fold_result actions ~init:state ~f:(fun curr_state act ->
      let%bind next_state, chained_events =
        eval_action curr_state act ~evt
      in
      List.fold_result
        chained_events
        ~init:next_state
        ~f:(process_event rules))
;;

let apply_action
  (rules : Ruleset.t)
  (state : Game_state.t)
  ~player_id
  ~(action : Action.Client_to_server.t)
  : Game_state.t Or_error.t
  =
  let%bind player =
    match List.nth state.players player_id with
    | Some p -> Ok p
    | None ->
      Or_error.error_s [%message "Player ID not found" (player_id : int)]
  in
  let%bind evt = Event.of_client_action state ~player ~action in
  process_event rules state evt
;;
