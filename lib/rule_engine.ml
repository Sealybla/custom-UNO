open! Core
open Or_error.Let_syntax

module Ruleset = struct
  type t = Rule.t list [@@deriving sexp, compare, equal, bin_io]

  (* special-card rules shared by EVERY variant: wild, skip, reverse. The +2/+4
     draw rules are intentionally NOT here — they differ between the standard
     and stacking rulesets (immediate vs deferred), so each variant appends its
     own below. *)
  let base_special_rules : t =
    [ { id = 1
      ; priority = 100
      ; condition = And (IsWildCard, IsPlayerTurn)
      ; actions =
          [ Mutate PlayTriggeringCard
          ; Mutate CheckWinner
          ; Mutate SetDeclaredColor
          ; Mutate AdvanceTurn
          ]
      }
    ; { id = 3
      ; priority = 100
      ; condition =
          And (IsSkip, And (Or (MatchesTopColor, MatchesTopValue), IsPlayerTurn))
      ; actions =
          [ Mutate PlayTriggeringCard
          ; Mutate CheckWinner
          ; Mutate SetColorFromTriggeringCard
          ; Mutate AdvanceTurn
          ; Mutate AdvanceTurn
          ]
      }
    ; { id = 4
      ; priority = 100
      ; condition =
          And (IsReverse, And (Or (MatchesTopColor, MatchesTopValue), IsPlayerTurn))
      ; actions =
          [ Mutate PlayTriggeringCard
          ; Mutate CheckWinner
          ; Mutate SetColorFromTriggeringCard
          ; Mutate ReverseDirection
          ; Mutate AdvanceTurn
          ]
      }
    ]
  ;;

  (* standard +2/+4: the NEXT player draws immediately and is skipped (two
     AdvanceTurns). Used by the default and draw-until rulesets. The +2 must
     match color or value like any other card; +4 is always playable. *)
  let immediate_draw_rules : t =
    [ { id = 2
      ; priority = 100
      ; condition =
          And (IsPlusTwo, And (Or (MatchesTopColor, MatchesTopValue), IsPlayerTurn))
      ; actions =
          [ Mutate PlayTriggeringCard
          ; Mutate CheckWinner
          ; Mutate SetColorFromTriggeringCard
          ; Mutate (DrawForNextPlayer 2)
          ; Mutate AdvanceTurn
          ; Mutate AdvanceTurn
          ]
      }
    ; { id = 8
      ; priority = 110
      ; condition = And (IsPlusFour, IsPlayerTurn)
      ; actions =
          [ Mutate PlayTriggeringCard
          ; Mutate CheckWinner
          ; Mutate SetDeclaredColor
          ; Mutate (DrawForNextPlayer 4)
          ; Mutate AdvanceTurn
          ; Mutate AdvanceTurn
          ]
      }
    ]
  ;;

  (* the stacking variant's wild/skip/reverse: same as the base specials but
     blocked while a stack is open, so mid-stack the only legal plays are
     same-value continuations (or a pass to close the stack) *)
  let stacking_special_rules : t =
    [ { id = 1
      ; priority = 100
      ; condition = And (IsWildCard, And (IsPlayerTurn, Not StackIsOpen))
      ; actions =
          [ Mutate PlayTriggeringCard
          ; Mutate CheckWinner
          ; Mutate SetDeclaredColor
          ; Mutate AdvanceTurn
          ]
      }
    ; { id = 3
      ; priority = 100
      ; condition =
          And
            ( IsSkip
            , And
                ( Or (MatchesTopColor, MatchesTopValue)
                , And (IsPlayerTurn, Not StackIsOpen) ) )
      ; actions =
          [ Mutate PlayTriggeringCard
          ; Mutate CheckWinner
          ; Mutate SetColorFromTriggeringCard
          ; Mutate AdvanceTurn
          ; Mutate AdvanceTurn
          ]
      }
    ; { id = 4
      ; priority = 100
      ; condition =
          And
            ( IsReverse
            , And
                ( Or (MatchesTopColor, MatchesTopValue)
                , And (IsPlayerTurn, Not StackIsOpen) ) )
      ; actions =
          [ Mutate PlayTriggeringCard
          ; Mutate CheckWinner
          ; Mutate SetColorFromTriggeringCard
          ; Mutate ReverseDirection
          ; Mutate AdvanceTurn
          ]
      }
    ]
  ;;

  (* stacking +2/+4: bump a shared counter (rule 5 cashes it out on the
     victim's turn), so the victim can stack their own +2/+4 first. Only used
     by the stacking variant; blocked mid-stack like the other specials. *)
  let deferred_draw_rules : t =
    [ { id = 2
      ; priority = 100
      ; condition =
          And
            ( IsPlusTwo
            , And
                ( Or (MatchesTopColor, MatchesTopValue)
                , And (IsPlayerTurn, Not StackIsOpen) ) )
      ; actions =
          [ Mutate PlayTriggeringCard
          ; Mutate CheckWinner
          ; Mutate SetColorFromTriggeringCard
          ; Mutate (AddPendingDraws 2)
          ; Mutate AdvanceTurn
          ]
      }
    ; { id = 8
      ; priority = 110
      ; condition = And (IsPlusFour, And (IsPlayerTurn, Not StackIsOpen))
      ; actions =
          [ Mutate PlayTriggeringCard
          ; Mutate CheckWinner
          ; Mutate SetDeclaredColor
          ; Mutate (AddPendingDraws 4)
          ; Mutate AdvanceTurn
          ]
      }
      (* while a penalty is pending, anything except stacking another +2/+4
         takes the cards - priority above the specials so a wild or skip
         cannot dodge it *)
    ; { id = 5
      ; priority = 105
      ; condition =
          And
            ( PendingDrawsGreaterThan 0
            , And (IsPlayerTurn, Not (Or (IsPlusTwo, IsPlusFour))) )
      ; actions = [ Mutate ApplyPendingDraws; Mutate AdvanceTurn ]
      }
    ]
  ;;

  (* generic play: number card matches, play it and advance (standard) *)
  let generic_play_rule : Rule.t =
    { id = 6
    ; priority = 10
    ; condition = And (Or (MatchesTopColor, MatchesTopValue), IsPlayerTurn)
    ; actions =
        [ Mutate PlayTriggeringCard
        ; Mutate CheckWinner
        ; Mutate SetColorFromTriggeringCard
        ; Mutate AdvanceTurn
        ]
    }
  ;;

  (* stacking: playing a card opens a same-value stack, turn stays open.
     Only fires when no stack is open yet — otherwise a same-color card
     could sneak into an open stack by "re-opening" it. *)
  let stack_open_rule : Rule.t =
    { id = 6
    ; priority = 10
    ; condition =
        And
          ( Or (MatchesTopColor, MatchesTopValue)
          , And (IsPlayerTurn, Not StackIsOpen) )
    ; actions =
        [ Mutate PlayTriggeringCard
        ; Mutate CheckWinner
        ; Mutate SetColorFromTriggeringCard
        ; Mutate SetStackingValue
          (* no AdvanceTurn — opens a stack; player passes to end turn *)
        ]
    }
  ;;

  (* continue an open stack — same value, stay on turn *)
  let stack_continue_rule : Rule.t =
    { id = 20
    ; priority = 120
    ; condition = And (ContinuesStack, IsPlayerTurn)
    ; actions =
        [ Mutate PlayTriggeringCard
        ; Mutate CheckWinner
        ; Mutate SetColorFromTriggeringCard
          (* no AdvanceTurn — stack stays open *)
        ]
    }
  ;;

  (* pass while a stack is open — clear the stack and end the turn *)
  let stack_pass_rule : Rule.t =
    { id = 21
    ; priority = 120
    ; condition = And (IsPassAction, And (IsPlayerTurn, StackIsOpen))
    ; actions = [ Mutate ClearStackingValue; Mutate AdvanceTurn ]
    }
  ;;

  (* draw one card; a playable draw keeps the turn open (play it or pass),
     an unplayable draw ends the turn. Blocked while deciding or mid-stack. *)
  let draw_decide_rule : Rule.t =
    { id = 7
    ; priority = 1
    ; condition =
        And
          ( IsDrawAction
          , And (IsPlayerTurn, And (Not StackIsOpen, Not DrewPlayableCard)) )
    ; actions = [ Mutate DrawAndDecide ]
    }
  ;;

  (* after drawing a playable card, passing ends the turn *)
  let pass_after_draw_rule : Rule.t =
    { id = 9
    ; priority = 1
    ; condition = And (IsPassAction, And (IsPlayerTurn, DrewPlayableCard))
    ; actions = [ Mutate AdvanceTurn ]
    }
  ;;

  (* each draw click takes one card and never ends the turn; drawn playable
     cards may be kept and drawing continued — with no pass rule in the
     variant, only actually playing a card ends the turn *)
  let draw_until_rule : Rule.t =
    { id = 7
    ; priority = 1
    ; condition = And (IsDrawAction, IsPlayerTurn)
    ; actions = [ Mutate (ExecuteDraw 1) ]
    }
  ;;

  (* draw-until inside the stacking variant: same idea, but no drawing
     while a stack is open *)
  let draw_until_stack_rule : Rule.t =
    { id = 7
    ; priority = 1
    ; condition = And (IsDrawAction, And (IsPlayerTurn, Not StackIsOpen))
    ; actions = [ Mutate (ExecuteDraw 1) ]
    }
  ;;

  let default : t =
    base_special_rules
    @ immediate_draw_rules
    @ [ generic_play_rule; draw_decide_rule; pass_after_draw_rule ]
  ;;

  let draw_until_variant : t =
    base_special_rules
    @ immediate_draw_rules
    @ [ generic_play_rule; draw_until_rule ]
  ;;

  let stacking_variant : t =
    stacking_special_rules
    @ deferred_draw_rules
    @ [ stack_open_rule
      ; stack_continue_rule
      ; stack_pass_rule
      ; draw_decide_rule
      ; pass_after_draw_rule
      ]
  ;;

  (* stacking play rules combined with draw-until drawing: chain same-value
     cards, and when stuck draw one card per click until you can play *)
  let stacking_draw_until_variant : t =
    stacking_special_rules
    @ deferred_draw_rules
    @ [ stack_open_rule
      ; stack_continue_rule
      ; stack_pass_rule
      ; draw_until_stack_rule
      ]
  ;;

  (* does any rule open a stack? tells the UI to mark stackable cards *)
  let uses_stacking (t : t) : bool =
    let rec opens_stack (act : Rule.Action_AST.t) =
      match act with
      | Mutate SetStackingValue -> true
      | Mutate _ | Chain_event _ -> false
      | Sequence acts -> List.exists acts ~f:opens_stack
    in
    List.exists t ~f:(fun rule -> List.exists rule.actions ~f:opens_stack)
  ;;
end

(* Convert network wire format into engine event format *)
let event_of_client_action
  (state : Game_state.t)
  ~player
  ~(action : Action.Client_to_server.t)
  : Event.t Or_error.t
  =
  match action with
  | Play { card_id; declared_color } ->
    let%map card =
      Game_state.Card_registry.find state.card_registry card_id
    in
    Event.CardPlayed { player; card; declared_color }
  | Draw -> Ok (DrawRequested { player })
  | Pass -> Ok (Event.PassRequested { player })
  | Join_lobby _ | Quit ->
    Or_error.error_s
      [%message "Non-gameplay action" (action : Action.Client_to_server.t)]
;;

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
  | IsPlayerTurn -> 
    (match evt with 
    | CardPlayed { player; _} | DrawRequested { player } | PassRequested { player } -> 
      Int.equal (Player.get_id player) state.turn)
  | IsSkip -> 
    (match evt with 
    | CardPlayed {card; _ } -> Card.Value.equal (Card.get_value card) Skip
    | _ -> false)
  | IsReverse -> 
    (match evt with 
    | CardPlayed { card; _} -> Card.Value.equal (Card.get_value card) Reverse 
    | _ -> false)
  | IsDrawAction -> 
    (match evt with 
    | DrawRequested _ -> true 
    | _ -> false )
  | IsPlusTwo -> 
    (match evt with 
    | CardPlayed { card; _ } -> Card.Value.equal (Card.get_value card) Plus 
    | _ -> false)
  | IsPlusFour -> 
    (match evt with 
    | CardPlayed {card; _} -> Card.Value.equal (Card.get_value card) Wild4 
    | _ -> false)
  | ContinuesStack ->
    (match evt with
    | CardPlayed {card ; _} ->
      (match state.stacking_value with
      | Some v -> Card.Value.equal (Card.get_value card) v
      | None -> false)
    | _ -> false)
  | StackIsOpen -> Option.is_some state.stacking_value
  | DrewPlayableCard -> state.drew_playable
  | IsPassAction ->
    (match evt with PassRequested _ -> true | _ -> false)
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
    let%map next_state = Game_state.apply_effect state ~event:evt eff in
    next_state, []
  | Chain_event evt -> Ok (state, [ evt ])
  | Sequence actions ->
    List.fold_result
      actions
      ~init:(state, [])
      ~f:(fun (curr_state, curr_evts) a ->
        let%map next_state, new_evts = eval_action curr_state ~evt a in
        next_state, curr_evts @ new_evts)
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
  match matching_rules with
    | [] ->
      (* short and clean: this text is shown to the player who acted *)
      Or_error.error_string "Illegal move: no rule allows that right now"
    | rule :: _ ->
      List.fold_result rule.actions ~init:state ~f:(fun curr_state act ->
        let%bind next_state, chained_events = eval_action curr_state act ~evt in
        List.fold_result chained_events ~init:next_state ~f:(process_event rules))
;;

(* would any rule accept a Pass from the current player right now? Used by
   the UI to decide whether the pass button is worth showing. *)
let pass_available (rules : Ruleset.t) (state : Game_state.t) : bool =
  match state.winner with
  | Some _ -> false
  | None ->
    (match List.nth state.players state.turn with
     | None -> false
     | Some player ->
       let evt = Event.PassRequested { player } in
       List.exists rules ~f:(fun (rule : Rule.t) ->
         eval_condition state evt rule.condition))
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
  let%bind evt = event_of_client_action state ~player ~action in
  process_event rules state evt
;;

(* Simulates every move the current player could make. When a pass is legal
   but no card play and no draw is, pressing the done button is a formality
   the server performs for them (e.g. mid-stack with nothing to continue). *)
let only_pass_available (rules : Ruleset.t) (state : Game_state.t) : bool =
  pass_available rules state
  &&
  match List.nth state.players state.turn with
  | None -> false
  | Some player ->
    let try_action action =
      apply_action rules state ~player_id:state.turn ~action |> Or_error.is_ok
    in
    (not
       (List.exists (Player.get_hand player) ~f:(fun card_id ->
          (* any real color works for simulating a wild's declaration *)
          try_action (Play { card_id; declared_color = Some Red }))))
    && not (try_action Draw)
;;
