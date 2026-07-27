open! Core
open Or_error.Let_syntax

module Ruleset = struct
  type t = Rule.t list [@@deriving sexp, compare, equal, bin_io]

  let default : t =
    [ (* play matching color *)
      { id = 1
      ; priority = 1
      ; condition = And (MatchesTopColor, IsPlayerTurn)
      ; actions =
          [ Sequence [ Mutate RemoveCardFromHand; Mutate SetTopCard ] ]
      }
    ; (* draw when forced *)
      { id = 2
      ; priority = 4
      ; condition =
          And (And (Not MatchesTopColor, Not MatchesTopValue), IsPlayerTurn)
      ; actions = [ Mutate ExecuteDraw ]
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

(* runs one action against the state. returns the updated state and a list 
of events the actions wants processed next*)
let rec eval_action (state : Game_state.t) (act : Rule.Action_AST.t)
  : (Game_state.t * Event.t list) Or_error.t
  =
  match act with
  (* change the state and emit no events. interprets the effect and returns the new state *)
  | Mutate eff ->
    (* apply effect implemented soon *)
    let%map next_state = Game_state.apply_effect state eff in
    (* the new state gets paired with an empty event list since there is nothing to change *)
    next_state, []
  (* change nothing but hand back one event for the engine to process *)
  | Chain_event evt -> Ok (state, [ evt ])
  (* run several actions in order, threading the state through each and collecting every event they emit*)
  | Sequence actions ->
    List.fold_result
      actions
      ~init:(state, [])
      ~f:(fun (curr_state, curr_evts) a ->
        let%map next_state, new_evts = eval_action curr_state a in
        next_state, curr_evts @ new_evts)
;;

(* finds the rules that allow this event, run their actions, and 
recurse on any events those actions emit. Returns the final state or an 
error if the move is illegal or an effect fails. *)
let rec process_event
  (rules : Ruleset.t)
  (state : Game_state.t)
  (evt : Event.t)
  : Game_state.t Or_error.t
  =
  (* doesn't process if someone has won*)
  let%bind () =
    match state.winner with
    | Some w -> Or_error.error_s [%message "Game is over" ~winner:(w : int)]
    | None -> Ok ()
  in
  (* order rules by priority *)
  let sorted_rules =
    List.sort rules ~compare:(fun r1 r2 ->
      Int.compare r2.priority r1.priority)
  in
  (* keeps only the rules whose condition holds for this event and state *)
  let matching_rules =
    List.filter sorted_rules ~f:(fun rule ->
      eval_condition state evt rule.condition)
  in

  match List.is_empty matching_rules with
  (* if no rule allows this event, then the move is illegal *)
  | true ->
    Or_error.error_s
      [%message "Illegal move: no matching rules" (evt : Event.t)]
  | false ->
    (* gets every action from every matching rule into one flat list *)
    let actions = List.concat_map matching_rules ~f:(fun r -> r.actions) in
    (* runs the actions in order*)
    List.fold_result actions ~init:state ~f:(fun curr_state act ->
      (* each action creates a new state and any events it wants processed next*)
      let%bind next_state, chained_events = eval_action curr_state act in
      List.fold_result
        chained_events
        ~init:next_state
        ~f:(process_event rules))
;;

(* what the server calls instead of the old apply_action. turns a raw client action into 
an event and feeds it to the rule engine *)
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
