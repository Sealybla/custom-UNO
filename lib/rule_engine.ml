open! Core
open Or_error.Let_syntax

module Ruleset = struct
  type t = Rule.t list [@@deriving sexp, compare, equal, bin_io]

  (* special-card rules shared by EVERY variant: wild, skip, reverse. The
     +2/+4 draw rules are intentionally NOT here — they differ between the
     standard and stacking rulesets (immediate vs deferred), so each variant
     appends its own below. *)
  let base_special_rules : t =
    [ { id = 1
      ; priority = 100
      ; condition = And (IsWildCard, IsPlayerTurn)
      ; actions =
          [ PlayTriggeringCard
          ; CheckWinner First_out
          ; SetDeclaredColor
          ; AdvanceTurn
          ]
      }
    ; { id = 3
      ; priority = 100
      ; condition =
          And
            ( IsSkip
            , And (Or (MatchesTopColor, MatchesTopValue), IsPlayerTurn) )
      ; actions =
          [ PlayTriggeringCard
          ; CheckWinner First_out
          ; SetColorFromTriggeringCard
          ; AdvanceTurn
          ; AdvanceTurn
          ]
      }
    ; { id = 4
      ; priority = 100
      ; condition =
          And
            ( IsReverse
            , And (Or (MatchesTopColor, MatchesTopValue), IsPlayerTurn) )
      ; actions =
          [ PlayTriggeringCard
          ; CheckWinner First_out
          ; SetColorFromTriggeringCard
          ; ReverseDirection
          ; AdvanceTurn
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
          And
            ( IsPlusTwo
            , And (Or (MatchesTopColor, MatchesTopValue), IsPlayerTurn) )
      ; actions =
          [ PlayTriggeringCard
          ; CheckWinner First_out
          ; SetColorFromTriggeringCard
          ; DrawForNextPlayer 2
          ; AdvanceTurn
          ; AdvanceTurn
          ]
      }
    ; { id = 8
      ; priority = 110
      ; condition = And (IsPlusFour, IsPlayerTurn)
      ; actions =
          [ PlayTriggeringCard
          ; CheckWinner First_out
          ; SetDeclaredColor
          ; DrawForNextPlayer 4
          ; AdvanceTurn
          ; AdvanceTurn
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
          [ PlayTriggeringCard
          ; CheckWinner First_out
          ; SetDeclaredColor
          ; AdvanceTurn
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
          [ PlayTriggeringCard
          ; CheckWinner First_out
          ; SetColorFromTriggeringCard
          ; AdvanceTurn
          ; AdvanceTurn
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
          [ PlayTriggeringCard
          ; CheckWinner First_out
          ; SetColorFromTriggeringCard
          ; ReverseDirection
          ; AdvanceTurn
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
          [ PlayTriggeringCard
          ; CheckWinner First_out
          ; SetColorFromTriggeringCard
          ; (AddPendingDraws 2)
          ; AdvanceTurn
          ]
      }
    ; { id = 8
      ; priority = 110
      ; condition = And (IsPlusFour, And (IsPlayerTurn, Not StackIsOpen))
      ; actions =
          [ PlayTriggeringCard
          ; CheckWinner First_out
          ; SetDeclaredColor
          ; (AddPendingDraws 4)
          ; AdvanceTurn
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
      ; actions = [ ApplyPendingDraws; AdvanceTurn ]
      }
    ]
  ;;

  (* generic play: number card matches, play it and advance (standard) *)
  let generic_play_rule : Rule.t =
    { id = 6
    ; priority = 10
    ; condition = And (Or (MatchesTopColor, MatchesTopValue), IsPlayerTurn)
    ; actions =
        [ PlayTriggeringCard
        ; CheckWinner First_out
        ; SetColorFromTriggeringCard
        ; AdvanceTurn
        ]
    }
  ;;

  (* stacking: playing a card opens a same-value stack, turn stays open. Only
     fires when no stack is open yet — otherwise a same-color card could
     sneak into an open stack by "re-opening" it. *)
  let stack_open_rule : Rule.t =
    { id = 6
    ; priority = 10
    ; condition =
        And
          ( Or (MatchesTopColor, MatchesTopValue)
          , And (IsPlayerTurn, Not StackIsOpen) )
    ; actions =
        [ PlayTriggeringCard
        ; CheckWinner First_out
        ; SetColorFromTriggeringCard
        ; SetStackingValue
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
        [ PlayTriggeringCard
        ; CheckWinner First_out
        ; SetColorFromTriggeringCard
          (* no AdvanceTurn — stack stays open *)
        ]
    }
  ;;

  (* pass while a stack is open — clear the stack and end the turn *)
  let stack_pass_rule : Rule.t =
    { id = 21
    ; priority = 120
    ; condition = And (IsPassAction, And (IsPlayerTurn, StackIsOpen))
    ; actions = [ ClearStackingValue; AdvanceTurn ]
    }
  ;;

  (* draw one card; a playable draw keeps the turn open (play it or pass), an
     unplayable draw ends the turn. Blocked while deciding or mid-stack. *)
  let draw_decide_rule : Rule.t =
    { id = 7
    ; priority = 1
    ; condition =
        And
          ( IsDrawAction
          , And (IsPlayerTurn, And (Not StackIsOpen, Not DrewPlayableCard))
          )
    ; actions = [ DrawAndDecide ]
    }
  ;;

  (* after drawing a playable card, passing ends the turn *)
  let pass_after_draw_rule : Rule.t =
    { id = 9
    ; priority = 1
    ; condition = And (IsPassAction, And (IsPlayerTurn, DrewPlayableCard))
    ; actions = [ AdvanceTurn ]
    }
  ;;

  (* each draw click takes one card and never ends the turn; drawn playable
     cards may be kept and drawing continued — with no pass rule in the
     variant, only actually playing a card ends the turn *)
  let draw_until_rule : Rule.t =
    { id = 7
    ; priority = 1
    ; condition = And (IsDrawAction, IsPlayerTurn)
    ; actions = [ (ExecuteDraw 1) ]
    }
  ;;

  (* draw-until inside the stacking variant: same idea, but no drawing
     while a stack is open *)
  let draw_until_stack_rule : Rule.t =
    { id = 7
    ; priority = 1
    ; condition = And (IsDrawAction, And (IsPlayerTurn, Not StackIsOpen))
    ; actions = [ (ExecuteDraw 1) ]
    }
  ;;

  (* The UNO button, in three rules ordered by priority: claiming your own
     UNO beats a bare press, and catching someone else always wins while a
     window is open - the "not someone has uno" guard is what lets a player
     who is themselves down to one card still make the catch (only one
     window can be open at a time, so the guard never blocks a self-claim).

     These sit above every other priority in the game on purpose. A few
     conditions (PendingDrawsGreaterThan, IsPlayerTurn) never look at the
     event, so a rule like "take penalty" would happily match an UNO press
     if it ever outranked these. The last rule matches any UNO press at all,
     so a press is always resolved here and never falls through. *)
  let uno_rules : t =
    [ { id = 30
      ; priority = 200
      ; condition = And (IsUnoCall, And (CallerHasUno, Not SomeoneElseHasUno))
      ; actions = [ MarkUnoCalled ]
      }
    ; { id = 31
      ; priority = 190
      ; condition = And (IsUnoCall, SomeoneElseHasUno)
      ; actions = [ (PenalizeUnoTarget 2) ]
      }
    ; { id = 32
      ; priority = 180
      ; condition = IsUnoCall
      ; actions = [ (PenalizeUnoCaller 2) ]
      }
    ]
  ;;

  (* Jump-in: play out of turn on an exact match of the top card. This is the
     one play rule that deliberately omits IsPlayerTurn - nothing else gates
     the turn, so leaving it out is all it takes. JumpToActor moves the turn
     to whoever played, and the AdvanceTurn after it carries on from there,
     so everyone in between loses their go.

     Number cards only: this rule's actions are the generic play sequence,
     so a jumped skip/reverse/+2 would land as a blank - and in the stacking
     variants a jumped +2 twin would leave the original pending penalty to
     fall on whoever holds the turn after the jump. A custom rule that
     spells out the card's effects can still allow action-card jumps.

     Blocked mid-stack: barging into someone's open stack would strand it. *)
  let jump_in_rules : t =
    [ { id = 40
      ; priority = 130
      ; condition =
          And
            ( MatchesTopExactly
            , And (Not IsActionCard, And (Not IsPlayerTurn, Not StackIsOpen))
            )
      ; actions =
          [ JumpToActor
          ; PlayTriggeringCard
          ; CheckWinner First_out
          ; SetColorFromTriggeringCard
          ; AdvanceTurn
          ]
      }
    ]
  ;;

  let default : t =
    base_special_rules
    @ immediate_draw_rules
    @ [ generic_play_rule; draw_decide_rule; pass_after_draw_rule ]
    @ uno_rules
  ;;

  let draw_until_variant : t =
    base_special_rules
    @ immediate_draw_rules
    @ [ generic_play_rule; draw_until_rule ]
    @ uno_rules
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
    @ uno_rules
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
    @ uno_rules
  ;;

  (* every variant above, again with jumping in allowed. Appended rather
     than woven in, so the preset texts can be built the same way. *)
  let jump_in_variant : t = default @ jump_in_rules
  let stacking_jump_in_variant : t = stacking_variant @ jump_in_rules
  let draw_until_jump_in_variant : t = draw_until_variant @ jump_in_rules

  let stacking_draw_until_jump_in_variant : t =
    stacking_draw_until_variant @ jump_in_rules
  ;;

  (* does any rule open a stack? tells the UI to mark stackable cards *)
  let uses_stacking (t : t) : bool =
    List.exists t ~f:(fun rule ->
      List.exists rule.actions ~f:(fun eff ->
        match eff with
        | Game_state.Effect.SetStackingValue -> true
        | _ -> false))
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
  | Play { card_id; declared_color; swap_with } ->
    let%bind card =
      Game_state.Card_registry.find state.card_registry card_id
    in
    let%map swap_with =
      match swap_with with
      | None -> Ok None
      | Some target_name ->
        (match
           List.find state.players ~f:(fun p ->
             String.Caseless.equal (Player.get_name p) target_name)
         with
         | None -> Or_error.errorf "No player named %s to swap with" target_name
         | Some target ->
           if Int.equal (Player.get_id target) (Player.get_id player)
           then Or_error.error_string "You cannot swap hands with yourself"
           else Ok (Some target))
    in
    Event.CardPlayed { player; card; declared_color; swap_with }
  | Draw -> Ok (DrawRequested { player })
  | Pass -> Ok (Event.PassRequested { player })
  | Call_uno -> Ok (Event.UnoCalled { player })
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
       (* an undeclared colour accepts anything, so a game that opens on a
          flipped wild lets the first player lead with any card *)
       Game_state.matches_color state ~played_card:card
     | _ -> false)
  | MatchesTopValue ->
    (match evt with
     | CardPlayed { card; _ } ->
       Card.Value.equal (Card.get_value card) (Card.get_value state.top_card)
     | _ -> false)
  | MatchesTopExactly ->
    (match evt with
     | CardPlayed { card; _ } ->
       (* a wild has no printed colour or number, so it never matches
          exactly - see the comment on the constructor *)
       let is_wild (c : Card.t) =
         match Card.get_value c with Wild | Wild4 -> true | _ -> false
       in
       (not (is_wild card))
       && (not (is_wild state.top_card))
       && Card.Color.equal (Card.get_color card) (Card.get_color state.top_card)
       && Card.Value.equal (Card.get_value card) (Card.get_value state.top_card)
     | _ -> false)
  | IsWildCard ->
    (match evt with
     | CardPlayed { card; _ } ->
       (match Card.get_value card with Wild | Wild4 -> true | _ -> false)
     | _ -> false)
  | PendingDrawsGreaterThan n -> state.pending_draws > n
  | IsPlayerTurn ->
    (match evt with
     | CardPlayed { player; _ }
     | DrawRequested { player }
     | PassRequested { player }
     (* an UNO press is not turn-gated, but asking is still meaningful *)
     | UnoCalled { player } -> Int.equal (Player.get_id player) state.turn)
  | IsSkip ->
    (match evt with
     | CardPlayed { card; _ } -> Card.Value.equal (Card.get_value card) Skip
     | _ -> false)
  | IsReverse ->
    (match evt with
     | CardPlayed { card; _ } ->
       Card.Value.equal (Card.get_value card) Reverse
     | _ -> false)
  | IsDrawAction -> (match evt with DrawRequested _ -> true | _ -> false)
  | IsPlusTwo ->
    (match evt with
     | CardPlayed { card; _ } -> Card.Value.equal (Card.get_value card) Plus
     | _ -> false)
  | IsPlusFour ->
    (match evt with
     | CardPlayed { card; _ } -> Card.Value.equal (Card.get_value card) Wild4
     | _ -> false)
  | IsNumber n ->
    (match evt with
     | CardPlayed { card; _ } ->
       (match Card.Value.of_digit n with
        | Some v -> Card.Value.equal (Card.get_value card) v
        (* unreachable via the parser, which rejects numbers outside 0-9 *)
        | None -> false)
     | _ -> false)
  | IsCardColor c ->
    (match evt with
     | CardPlayed { card; _ } -> Card.Color.equal (Card.get_color card) c
     | _ -> false)
  | IsActionCard ->
    (match evt with
     | CardPlayed { card; _ } ->
       (match Card.get_value card with
        | Skip | Reverse | Plus | Wild | Wild4 -> true
        | _ -> false)
     | _ -> false)
  | IsNumberCard ->
    (match evt with
     | CardPlayed { card; _ } ->
       (match Card.get_value card with
        | Skip | Reverse | Plus | Wild | Wild4 -> false
        | _ -> true)
     | _ -> false)
  | ActiveColorIs c -> Card.Color.equal state.current_color c
  (* the ACTING player's hand as it stands when the rule is judged - for a
     card play that is BEFORE the card leaves the hand, so "their last
     card" is [hand size = 1] *)
  | HandSizeGreaterThan n ->
    (match evt with
     | CardPlayed { player; _ }
     | DrawRequested { player }
     | PassRequested { player }
     | UnoCalled { player } ->
       Game_state.hand_size state (Player.get_id player) > n)
  | HandSizeEquals n ->
    (match evt with
     | CardPlayed { player; _ }
     | DrawRequested { player }
     | PassRequested { player }
     | UnoCalled { player } ->
       Game_state.hand_size state (Player.get_id player) = n)
  (* "opponent" = any player other than the actor. Their hands are never
     mid-change when a rule is judged, so there is no before/after subtlety
     like the actor's own hand has *)
  | AnyOpponentHandEquals n ->
    (match evt with
     | CardPlayed { player; _ }
     | DrawRequested { player }
     | PassRequested { player }
     | UnoCalled { player } ->
       List.exists state.players ~f:(fun p ->
         (not (Int.equal (Player.get_id p) (Player.get_id player)))
         && List.length (Player.get_hand p) = n))
  | AnyOpponentHandGreaterThan n ->
    (match evt with
     | CardPlayed { player; _ }
     | DrawRequested { player }
     | PassRequested { player }
     | UnoCalled { player } ->
       List.exists state.players ~f:(fun p ->
         (not (Int.equal (Player.get_id p) (Player.get_id player)))
         && List.length (Player.get_hand p) > n))
  | TopCardIsNumber n ->
    (match Card.Value.of_digit n with
     | Some v -> Card.Value.equal (Card.get_value state.top_card) v
     (* unreachable via the parser, which rejects numbers outside 0-9 *)
     | None -> false)
  | TopCardIsAction ->
    (match Card.get_value state.top_card with
     | Skip | Reverse | Plus | Wild | Wild4 -> true
     | _ -> false)
  | DirectionIsClockwise -> Direction.equal state.direction Clockwise
  | DrawPileLessThan n -> List.length state.draw_pile < n
  | ContinuesStack ->
    (match evt with
     | CardPlayed { card; _ } ->
       (match state.stacking_value with
        | Some v -> Card.Value.equal (Card.get_value card) v
        | None -> false)
     | _ -> false)
  | StackIsOpen -> Option.is_some state.stacking_value
  | DrewPlayableCard -> state.drew_playable
  | IsPassAction -> (match evt with PassRequested _ -> true | _ -> false)
  | IsUnoCall -> (match evt with UnoCalled _ -> true | _ -> false)
  | CallerHasUno ->
    (* deliberately "holds one card", not "is catchable": a player whose
       window already closed should still be able to press the button
       without being fined for it *)
    (match evt with
     | UnoCalled { player } ->
       Int.equal (Game_state.hand_size state (Player.get_id player)) 1
     | _ -> false)
  | SomeoneElseHasUno ->
    (match evt with
     | UnoCalled { player } ->
       (match state.uno_vulnerable with
        | Some victim -> not (Int.equal victim (Player.get_id player))
        | None -> false)
     | _ -> false)
  | And (c1, c2) ->
    eval_condition state evt c1 && eval_condition state evt c2
  | Or (c1, c2) -> eval_condition state evt c1 || eval_condition state evt c2
  | Not c -> not (eval_condition state evt c)
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
  (* highest priority first; among equal priorities the lower id wins, and
     the parser assigns ids in definition order - so "priority first, then
     the rule defined first" is guaranteed explicitly, not via sort
     stability *)
  let sorted_rules =
    List.sort rules ~compare:(fun r1 r2 ->
      match Int.compare r2.priority r1.priority with
      | 0 -> Int.compare r1.id r2.id
      | c -> c)
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
    List.fold_result rule.actions ~init:state ~f:(fun curr_state eff ->
      Game_state.apply_effect
        ~card_playable:(ruleset_accepts_play rules)
        curr_state
        ~event:evt
        eff)

(* would this ruleset accept playing [played_card] right now? The draw
   effects ask this about the card they just drew, so "playable" there
   means exactly what it means for the UI highlights: whatever the rules
   in force would actually allow, not official-rules matching. Mirrors
   playable_and_swap_ids: any real colour stands in for a wild's
   declaration, and failing only for want of a target still counts. *)
and ruleset_accepts_play rules state ~player_id ~(played_card : Card.t) =
  match
    apply_action
      rules
      state
      ~player_id
      ~action:
        (Action.Client_to_server.Play
           { card_id = Card.get_id played_card
           ; declared_color = Some Red
           ; swap_with = None
           })
  with
  | Ok _ -> true
  | Error e ->
    String.is_substring
      (Error.to_string_hum e)
      ~substring:Game_state.target_needed

and apply_action
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
  let%map next_state = process_event rules state evt in
  (* window bookkeeping sits outside the ruleset on purpose - see
     Game_state.update_uno_window *)
  Game_state.update_uno_window next_state ~actor_id:player_id ~event:evt
;;

(* would the ruleset actually accept a Pass from the current player right
   now? Simulated like every other availability check. The old shortcut -
   "does any rule's condition match" - contradicted execution, which runs
   only the highest-priority match: a reject-on-pass rule above a
   permissive one made the UI offer a pass that could never land. *)
let pass_available (rules : Ruleset.t) (state : Game_state.t) : bool =
  apply_action rules state ~player_id:state.turn ~action:Pass
  |> Or_error.is_ok
;;

(* Which of this player's cards the ruleset would accept right now, found by
   simulating each play. Asking the engine rather than reimplementing card
   legality is what keeps the UI honest for rules it has never heard of -
   an out-of-turn jump-in shows up here for free, whatever condition the
   player wrote for it. Cheap: a hand times a ruleset is a few hundred
   condition checks. *)
(* (playable ids, subset that also needs a swap target). A play that fails
   only for want of a target IS legal - the UI just has to ask who first. *)
let playable_and_swap_ids (rules : Ruleset.t) (state : Game_state.t) ~player_id
  : int list * int list
  =
  match state.winner with
  | Some _ -> [], []
  | None ->
    (match List.nth state.players player_id with
     | None -> [], []
     | Some player ->
       let statuses =
         List.filter_map (Player.get_hand player) ~f:(fun card_id ->
           (* any real colour stands in for a wild's declaration *)
           match
             apply_action
               rules
               state
               ~player_id
               ~action:
                 (Play { card_id; declared_color = Some Red; swap_with = None })
           with
           | Ok _ -> Some (card_id, `Ready)
           | Error e ->
             if String.is_substring
                  (Error.to_string_hum e)
                  ~substring:Game_state.target_needed
             then Some (card_id, `Needs_target)
             else None)
       in
       ( List.map statuses ~f:fst
       , List.filter_map statuses ~f:(function
           | id, `Needs_target -> Some id
           | _, `Ready -> None) ))
;;

let playable_card_ids (rules : Ruleset.t) (state : Game_state.t) ~player_id
  : int list
  =
  fst (playable_and_swap_ids rules state ~player_id)
;;

(* Simulates every move the current player could make. When a pass is legal
   but no card play and no draw is, pressing the done button is a formality
   the server performs for them (e.g. mid-stack with nothing to continue). *)
let only_pass_available (rules : Ruleset.t) (state : Game_state.t) : bool =
  pass_available rules state
  && List.is_empty (playable_card_ids rules state ~player_id:state.turn)
  && not
       (apply_action rules state ~player_id:state.turn ~action:Draw
        |> Or_error.is_ok)
;;
