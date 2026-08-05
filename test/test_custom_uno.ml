open! Core
open Custom_uno

let make_state () =
  Game_state.create
    ~random_state:(Random.State.make [| 42 |])
    ~player_names:[ "alice"; "bob"; "carol" ]
    ~hand_size:7
    ()
  |> Or_error.ok_exn
;;

let%expect_test "deck is 108 cards" =
  let deck = Game_state.create_card_deck () in
  print_s [%message (List.length deck : int)];
  [%expect {| ("List.length deck" 108) |}]
;;

let%expect_test "deck ids are unique" =
  let deck = Game_state.create_card_deck () in
  let ids = List.map deck ~f:Card.get_id in
  let unique = List.dedup_and_sort ids ~compare:Int.compare in
  print_s [%message (List.length ids : int) (List.length unique : int)];
  [%expect {| (("List.length ids" 108) ("List.length unique" 108)) |}]
;;

let%expect_test "create deals correctly" =
  let t = make_state () in
  let hand_sizes =
    List.map t.players ~f:(fun p -> List.length (Player.get_hand p))
  in
  print_s
    [%message
      (hand_sizes : int list)
        (List.length t.draw_pile : int)
        (t.turn : int)
        (t.winner : int option)];
  [%expect
    {|
    ((hand_sizes (7 7 7)) ("List.length t.draw_pile" 86) (t.turn 0)
     (t.winner ()))
    |}]
;;

let%expect_test "same seed gives same deal" =
  let t = make_state () in
  let t2 = make_state () in
  print_s [%message (List.equal Card.equal t.draw_pile t2.draw_pile : bool)];
  [%expect {| ("List.equal Card.equal t.draw_pile t2.draw_pile" true) |}]
;;

let%expect_test "shuffle is seeded" =
  let deck = Game_state.create_card_deck () in
  let rs () = Random.State.make [| 42 |] in
  let a = Game_state.shuffle ~random_state:(rs ()) deck in
  let b = Game_state.shuffle ~random_state:(rs ()) deck in
  print_s [%message (List.equal Card.equal a b : bool)];
  [%expect {| ("List.equal Card.equal a b" true) |}]
;;

let%expect_test "draw pile is shuffled" =
  let t = make_state () in
  let first_ten = List.take (List.map t.draw_pile ~f:Card.get_id) 10 in
  print_s [%message (first_ten : int list)];
  [%expect {| (first_ten (19 23 94 89 73 84 85 22 96 92)) |}]
;;

(* drawing an unplayable card ends the turn *)
let%expect_test "engine processes a draw" =
  let top = { Card.color = Red; value = Five; id = 900 } in
  let unplayable = { Card.color = Blue; value = Two; id = 901 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", []; "b", [] ]
      ~top_card:top
      ~draw_pile:[ unplayable ]
      ~pending_draws:0
      ~turn:0
  in
  let t' =
    Rule_engine.apply_action
      Rule_engine.Ruleset.default
      t
      ~player_id:0
      ~action:Draw
    |> Or_error.ok_exn
  in
  let after = List.length (Player.get_hand (List.nth_exn t'.players 0)) in
  print_s [%message (after : int) (t'.turn : int) (t'.drew_playable : bool)];
  [%expect {| ((after 1) (t'.turn 1) (t'.drew_playable false)) |}]
;;

(* drawing a playable card keeps the turn open: the player may play it or
   pass; passing ends the turn *)
let%expect_test "playable draw offers play-or-pass" =
  let top = { Card.color = Red; value = Five; id = 910 } in
  let playable = { Card.color = Red; value = Nine; id = 911 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", []; "b", [] ]
      ~top_card:top
      ~draw_pile:[ playable ]
      ~pending_draws:0
      ~turn:0
  in
  let t =
    Rule_engine.apply_action
      Rule_engine.Ruleset.default
      t
      ~player_id:0
      ~action:Draw
    |> Or_error.ok_exn
  in
  print_s
    [%message
      "after draw"
        (t.turn : int)
        (t.drew_playable : bool)
        (Rule_engine.pass_available Rule_engine.Ruleset.default t : bool)];
  (* drawing again while deciding is not allowed *)
  let redraw =
    Rule_engine.apply_action
      Rule_engine.Ruleset.default
      t
      ~player_id:0
      ~action:Draw
  in
  print_s [%message (Or_error.is_error redraw : bool)];
  let t =
    Rule_engine.apply_action
      Rule_engine.Ruleset.default
      t
      ~player_id:0
      ~action:Pass
    |> Or_error.ok_exn
  in
  print_s [%message "after pass" (t.turn : int) (t.drew_playable : bool)];
  [%expect
    {|
    ("after draw" (t.turn 0) (t.drew_playable true)
     ("Rule_engine.pass_available Rule_engine.Ruleset.default t" true))
    ("Or_error.is_error redraw" true)
    ("after pass" (t.turn 1) (t.drew_playable false))
    |}]
;;

(* the pass button has no job unless a drawn playable card is waiting *)
let%expect_test "cannot pass without drawing a playable card first" =
  let top = { Card.color = Red; value = Five; id = 920 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", []; "b", [] ]
      ~top_card:top
      ~draw_pile:[]
      ~pending_draws:0
      ~turn:0
  in
  let result =
    Rule_engine.apply_action
      Rule_engine.Ruleset.default
      t
      ~player_id:0
      ~action:Pass
  in
  print_s
    [%message
      (Or_error.is_error result : bool)
        (Rule_engine.pass_available Rule_engine.Ruleset.default t : bool)];
  [%expect
    {|
    (("Or_error.is_error result" true)
     ("Rule_engine.pass_available Rule_engine.Ruleset.default t" false))
    |}]
;;

let%expect_test "full game plays to completion" =
  let resolve_hand state player =
    List.filter_map (Player.get_hand player) ~f:(fun id ->
      Game_state.Card_registry.find state.Game_state.card_registry id
      |> Or_error.ok)
  in
  let rec play state moves =
    if moves > 1000
    then (
      print_endline "no winner after 1000 moves";
      let sizes =
        List.map state.Game_state.players ~f:(fun p ->
          List.length (Player.get_hand p))
      in
      print_s
        [%message
          (sizes : int list)
            (state.Game_state.turn : int)
            (List.length state.Game_state.draw_pile : int)])
    else (
      match state.Game_state.winner with
      | Some id -> print_s [%message "winner" (id : int) (moves : int)]
      | None ->
        let player =
          List.nth_exn state.Game_state.players state.Game_state.turn
        in
        let hand = resolve_hand state player in
        let action =
          match Game_state.first_playable_card state ~hand with
          | Some card ->
            let declared_color =
              match card.Card.value with
              | Wild | Wild4 ->
                Some
                  (List.find_map hand ~f:(fun c ->
                     match c.Card.color with
                     | NoColor -> None
                     | col -> Some col)
                   |> Option.value ~default:Card.Color.Red)
              | _ -> None
            in
            Action.Client_to_server.Play
              { card_id = Card.get_id card; declared_color; swap_with = None }
          | None -> Draw
        in
        (match
           Rule_engine.apply_action
             Rule_engine.Ruleset.default
             state
             ~player_id:state.Game_state.turn
             ~action
         with
         | Ok next -> play next (moves + 1)
         | Error e -> print_s [%message "stuck" (e : Error.t) (moves : int)]))
  in
  play (make_state ()) 0;
  [%expect {| (winner (id 0) (moves 28)) |}]
;;

let%expect_test "plus2 stacks then cashes out" =
  let p2a = { Card.color = Red; value = Plus; id = 200 } in
  let p2b = { Card.color = Blue; value = Plus; id = 201 } in
  let top = { Card.color = Green; value = Plus; id = 202 } in
  let f1 = { Card.color = Red; value = Zero; id = 203 } in
  let f2 = { Card.color = Red; value = Zero; id = 204 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", [ p2a; f1 ]; "b", [ p2b; f2 ]; "c", [] ]
      ~top_card:top
      ~draw_pile:(Game_state.create_card_deck ())
      ~pending_draws:2
      ~turn:1
  in
  (* player 1 stacks their Plus2 — pending should go 2 -> 4, turn 1 -> 2 *)
  let t =
    Rule_engine.apply_action
      Rule_engine.Ruleset.stacking_variant
      t
      ~player_id:1
      ~action:(Play { card_id = 201; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  print_s [%message "after stack" (t.pending_draws : int) (t.turn : int)];
  (* player 2 can't stack — draws the pending 4, pending resets to 0 *)
  let before = List.length (Player.get_hand (List.nth_exn t.players 2)) in
  let t =
    Rule_engine.apply_action
      Rule_engine.Ruleset.stacking_variant
      t
      ~player_id:2
      ~action:Draw
    |> Or_error.ok_exn
  in
  let after = List.length (Player.get_hand (List.nth_exn t.players 2)) in
  print_s
    [%message
      "after penalty draw"
        (before : int)
        (after : int)
        (t.pending_draws : int)
        (t.turn : int)];
  [%expect
    {|
    ("after stack" (t.pending_draws 4) (t.turn 2))
    ("after penalty draw" (before 0) (after 4) (t.pending_draws 0) (t.turn 0))
    |}]
;;

let%expect_test "plus4 stacks then cashes out" =
  let p4 = { Card.color = NoColor; value = Wild4; id = 300 } in
  let top = { Card.color = Green; value = Plus; id = 301 } in
  let f1 = { Card.color = Red; value = Zero; id = 302 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", []; "b", [ p4; f1 ]; "c", [] ]
      ~top_card:top
      ~draw_pile:(Game_state.create_card_deck ())
      ~pending_draws:2
      ~turn:1
  in
  (* player 1 stacks a Plus4 onto a pending 2 — pending 2 -> 6 *)
  let t =
    Rule_engine.apply_action
      Rule_engine.Ruleset.stacking_variant
      t
      ~player_id:1
      ~action:(Play { card_id = 300; declared_color = Some Red; swap_with = None })
    |> Or_error.ok_exn
  in
  print_s
    [%message "after plus4 stack" (t.pending_draws : int) (t.turn : int)];
  (* player 2 can't continue — draws all 6, pending resets *)
  let before = List.length (Player.get_hand (List.nth_exn t.players 2)) in
  let t =
    Rule_engine.apply_action
      Rule_engine.Ruleset.stacking_variant
      t
      ~player_id:2
      ~action:Draw
    |> Or_error.ok_exn
  in
  let after = List.length (Player.get_hand (List.nth_exn t.players 2)) in
  print_s
    [%message
      "after penalty draw"
        (before : int)
        (after : int)
        (t.pending_draws : int)
        (t.turn : int)];
  [%expect
    {|
    ("after plus4 stack" (t.pending_draws 6) (t.turn 2))
    ("after penalty draw" (before 0) (after 6) (t.pending_draws 0) (t.turn 0))
    |}]
;;

(* each click draws one card and the turn stays put; there is no pass in
   this variant, so a drawn playable card can be kept and drawing goes on
   — only actually playing a card ends the turn *)
let%expect_test "draw until playable: one card per click, play is the only exit" =
  let top = { Card.color = Red; value = Five; id = 400 } in
  (* draw pile: unplayable, playable, unplayable *)
  let d1 = { Card.color = Blue; value = Two; id = 401 } in   (* not red, not 5 *)
  let d2 = { Card.color = Red; value = Nine; id = 402 } in    (* red — playable *)
  let d3 = { Card.color = Green; value = Eight; id = 403 } in (* not red, not 5 *)
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", []; "b", [] ]
      ~top_card:top
      ~draw_pile:[ d1; d2; d3 ]
      ~pending_draws:0
      ~turn:0
  in
  let rules = Rule_engine.Ruleset.draw_until_variant in
  let draw t =
    Rule_engine.apply_action rules t ~player_id:0 ~action:Draw |> Or_error.ok_exn
  in
  let report label (t : Game_state.t) =
    let hand = List.length (Player.get_hand (List.nth_exn t.players 0)) in
    print_s
      [%message
        label (hand : int) (t.turn : int)
          (Rule_engine.pass_available rules t : bool)]
  in
  let t = draw t in
  report "click 1 (unplayable)" t;
  let t = draw t in
  report "click 2 (playable)" t;
  (* passing is never legal, even holding a playable draw *)
  let pass = Rule_engine.apply_action rules t ~player_id:0 ~action:Pass in
  print_s [%message (Or_error.is_error pass : bool)];
  (* the playable card may be kept: drawing again is still allowed *)
  let t = draw t in
  report "click 3 (kept it)" t;
  (* playing a card is what finally ends the turn *)
  let t =
    Rule_engine.apply_action rules t ~player_id:0
      ~action:(Play { card_id = 402; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  report "after play" t;
  [%expect {|
    ("click 1 (unplayable)" (hand 1) (t.turn 0)
     ("Rule_engine.pass_available rules t" false))
    ("click 2 (playable)" (hand 2) (t.turn 0)
     ("Rule_engine.pass_available rules t" false))
    ("Or_error.is_error pass" true)
    ("click 3 (kept it)" (hand 3) (t.turn 0)
     ("Rule_engine.pass_available rules t" false))
    ("after play" (hand 2) (t.turn 1)
     ("Rule_engine.pass_available rules t" false))
    |}]
;;


(* mid-stack with no continuation in hand, done is a formality: the server
   detects pass as the only legal move; holding another card of the stacked
   value (or a playable drawn card in the default rules) keeps real choices *)
let%expect_test "only-pass detection" =
  let top = { Card.color = Red; value = Three; id = 700 } in
  let seven = { Card.color = Red; value = Seven; id = 701 } in
  let other_seven = { Card.color = Blue; value = Seven; id = 702 } in
  let off_card = { Card.color = Blue; value = Two; id = 703 } in
  let rules = Rule_engine.Ruleset.stacking_variant in
  let open_stack hand =
    let t =
      Game_state.for_testing
        ~player_hands:[ "a", hand; "b", [] ]
        ~top_card:top
        ~draw_pile:(Game_state.create_card_deck ())
        ~pending_draws:0
        ~turn:0
    in
    Rule_engine.apply_action rules t ~player_id:0
      ~action:(Play { card_id = 701; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  let stuck = open_stack [ seven; off_card ] in
  print_s
    [%message
      "no continuation" (Rule_engine.only_pass_available rules stuck : bool)];
  let choices = open_stack [ seven; other_seven ] in
  print_s
    [%message
      "another seven in hand"
        (Rule_engine.only_pass_available rules choices : bool)];
  (* default rules: a drawn playable card can always be played, so a pass
     there is never the only move *)
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", []; "b", [] ]
      ~top_card:{ Card.color = Red; value = Five; id = 710 }
      ~draw_pile:[ { Card.color = Red; value = Nine; id = 711 } ]
      ~pending_draws:0
      ~turn:0
  in
  let t =
    Rule_engine.apply_action Rule_engine.Ruleset.default t ~player_id:0
      ~action:Draw
    |> Or_error.ok_exn
  in
  print_s
    [%message
      "drew a playable card"
        (Rule_engine.pass_available Rule_engine.Ruleset.default t : bool)
        (Rule_engine.only_pass_available Rule_engine.Ruleset.default t : bool)];
  [%expect
    {|
    ("no continuation" ("Rule_engine.only_pass_available rules stuck" true))
    ("another seven in hand"
     ("Rule_engine.only_pass_available rules choices" false))
    ("drew a playable card"
     ("Rule_engine.pass_available Rule_engine.Ruleset.default t" true)
     ("Rule_engine.only_pass_available Rule_engine.Ruleset.default t" false))
    |}]
;;

let%expect_test "stacking same number plays multiple in one turn" =
  let s1 = { Card.color = Red; value = Seven; id = 500 } in
  let s2 = { Card.color = Blue; value = Seven; id = 501 } in
  let top = { Card.color = Red; value = Three; id = 502 } in
  let f = { Card.color = Green; value = Zero; id = 503 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", [ s1; s2; f ]; "b", []; "c", [] ]
      ~top_card:top
      ~draw_pile:(Game_state.create_card_deck ())
      ~pending_draws:0
      ~turn:0
  in
  (* play first 7 — opens stack, turn stays 0 *)
  let t =
    Rule_engine.apply_action
      Rule_engine.Ruleset.stacking_variant
      t
      ~player_id:0
      ~action:(Play { card_id = 500; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  print_s
    [%message
      "after first 7"
        (t.turn : int)
        (t.stacking_value : Card.Value.t option)
        (List.length (Player.get_hand (List.nth_exn t.players 0)) : int)];
  (* play second 7 — continues stack, turn still 0 *)
  let t =
    Rule_engine.apply_action
      Rule_engine.Ruleset.stacking_variant
      t
      ~player_id:0
      ~action:(Play { card_id = 501; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  print_s
    [%message
      "after second 7"
        (t.turn : int)
        (List.length (Player.get_hand (List.nth_exn t.players 0)) : int)];
  (* pass — ends turn, clears stack *)
  let t =
    Rule_engine.apply_action
      Rule_engine.Ruleset.stacking_variant
      t
      ~player_id:0
      ~action:Pass
    |> Or_error.ok_exn
  in
  print_s
    [%message
      "after pass" (t.turn : int) (t.stacking_value : Card.Value.t option)];
  [%expect
    {|
    ("after first 7" (t.turn 0) (t.stacking_value (Seven))
     ("List.length (Player.get_hand (List.nth_exn t.players 0))" 2))
    ("after second 7" (t.turn 0)
     ("List.length (Player.get_hand (List.nth_exn t.players 0))" 1))
    ("after pass" (t.turn 1) (t.stacking_value ()))
    |}]
;;

(* regression: after opening a stack, a same-COLOR different-value card used
   to slip in by re-triggering "open stack"; mid-stack only same-value
   continuations (or a pass) are legal *)
let%expect_test "open stack locks the turn to same-value cards" =
  let seven_r = { Card.color = Red; value = Seven; id = 650 } in
  let seven_b = { Card.color = Blue; value = Seven; id = 651 } in
  let three_r = { Card.color = Red; value = Three; id = 652 } in
  let skip_r = { Card.color = Red; value = Skip; id = 653 } in
  let wild = { Card.color = NoColor; value = Wild; id = 654 } in
  let top = { Card.color = Red; value = Two; id = 655 } in
  let t =
    Game_state.for_testing
      ~player_hands:
        [ "a", [ seven_r; seven_b; three_r; skip_r; wild ]; "b", [] ]
      ~top_card:top
      ~draw_pile:(Game_state.create_card_deck ())
      ~pending_draws:0
      ~turn:0
  in
  (* open the stack with the red 7 *)
  let t =
    Rule_engine.apply_action
      Rule_engine.Ruleset.stacking_variant
      t
      ~player_id:0
      ~action:(Play { card_id = 650; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  let rejected action =
    Rule_engine.apply_action
      Rule_engine.Ruleset.stacking_variant
      t
      ~player_id:0
      ~action
    |> Or_error.is_error
  in
  (* same color but different value, a special, and a draw are all illegal *)
  let red_three_rejected =
    rejected (Play { card_id = 652; declared_color = None; swap_with = None })
  in
  let red_skip_rejected =
    rejected (Play { card_id = 653; declared_color = None; swap_with = None })
  in
  let wild_rejected =
    rejected (Play { card_id = 654; declared_color = Some Red; swap_with = None })
  in
  let draw_rejected = rejected Draw in
  (* the blue 7 continues the stack *)
  let t =
    Rule_engine.apply_action
      Rule_engine.Ruleset.stacking_variant
      t
      ~player_id:0
      ~action:(Play { card_id = 651; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  print_s
    [%message
      (red_three_rejected : bool)
        (red_skip_rejected : bool)
        (wild_rejected : bool)
        (draw_rejected : bool)
        (t.turn : int)
        (t.stacking_value : Card.Value.t option)];
  [%expect
    {|
    ((red_three_rejected true) (red_skip_rejected true) (wild_rejected true)
     (draw_rejected true) (t.turn 0) (t.stacking_value (Seven)))
    |}]
;;

(* regression: stacking_value used to start as [Some Zero], which let an
   unmatching Zero be "continued" onto a fresh game with no stack open *)
let%expect_test "non-matching zero is rejected when no stack is open" =
  let z = { Card.color = Blue; value = Zero; id = 600 } in
  let top = { Card.color = Red; value = Five; id = 601 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", [ z ]; "b", [] ]
      ~top_card:top
      ~draw_pile:[]
      ~pending_draws:0
      ~turn:0
  in
  let result =
    Rule_engine.apply_action
      Rule_engine.Ruleset.stacking_variant
      t
      ~player_id:0
      ~action:(Play { card_id = 600; declared_color = None; swap_with = None })
  in
  print_s [%message (Or_error.is_error result : bool)];
  [%expect {| ("Or_error.is_error result" true) |}]
;;

(* regression: MatchesTopColor used to also accept NoColor cards; wilds must
   only be playable through their dedicated rule *)
let%expect_test "MatchesTopColor is false for wilds but wilds still play" =
  let w = { Card.color = NoColor; value = Wild; id = 610 } in
  let top = { Card.color = Red; value = Five; id = 611 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", [ w ]; "b", [] ]
      ~top_card:top
      ~draw_pile:[]
      ~pending_draws:0
      ~turn:0
  in
  let evt =
    Event.CardPlayed
      { player = List.nth_exn t.players 0
      ; card = w
      ; declared_color = Some Red
      ; swap_with = None
      }
  in
  print_s
    [%message (Rule_engine.eval_condition t evt MatchesTopColor : bool)];
  let result =
    Rule_engine.apply_action
      Rule_engine.Ruleset.default
      t
      ~player_id:0
      ~action:(Play { card_id = 610; declared_color = Some Red; swap_with = None })
  in
  print_s [%message (Or_error.is_ok result : bool)];
  [%expect
    {|
    ("Rule_engine.eval_condition t evt MatchesTopColor" false)
    ("Or_error.is_ok result" true)
    |}]
;;

(* regression: action cards (skip/reverse/+2) used to be playable on ANY
   color because their rules only checked the card type, not a color/value
   match *)
let%expect_test "skip/reverse must match color or value" =
  let red_skip = { Card.color = Red; value = Skip; id = 620 } in
  let blue_top = { Card.color = Blue; value = Five; id = 621 } in
  let try_play card ~top =
    let t =
      Game_state.for_testing
        ~player_hands:[ "a", [ card ]; "b", [] ]
        ~top_card:top
        ~draw_pile:(Game_state.create_card_deck ())
        ~pending_draws:0
        ~turn:0
    in
    Rule_engine.apply_action
      Rule_engine.Ruleset.default
      t
      ~player_id:0
      ~action:(Play { card_id = Card.get_id card; declared_color = None; swap_with = None })
    |> Or_error.is_ok
  in
  let on_wrong_color = try_play red_skip ~top:blue_top in
  let on_matching_color =
    try_play red_skip ~top:{ Card.color = Red; value = Five; id = 622 }
  in
  let on_matching_value =
    try_play red_skip ~top:{ Card.color = Blue; value = Skip; id = 623 }
  in
  print_s
    [%message
      (on_wrong_color : bool)
        (on_matching_color : bool)
        (on_matching_value : bool)];
  [%expect
    {| ((on_wrong_color false) (on_matching_color true) (on_matching_value true)) |}]
;;

(* regression: special cards must match color or value like any other card *)
let%expect_test "non-matching special cards are rejected" =
  let p2 = { Card.color = Blue; value = Plus; id = 800 } in
  let skip = { Card.color = Green; value = Skip; id = 801 } in
  let top = { Card.color = Red; value = Five; id = 802 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", [ p2; skip ]; "b", [] ]
      ~top_card:top
      ~draw_pile:[]
      ~pending_draws:0
      ~turn:0
  in
  let try_play id =
    Rule_engine.apply_action
      Rule_engine.Ruleset.default
      t
      ~player_id:0
      ~action:(Play { card_id = id; declared_color = None; swap_with = None })
    |> Or_error.is_error
  in
  let blue_plus_on_red_five_rejected = try_play 800 in
  let green_skip_on_red_five_rejected = try_play 801 in
  print_s
    [%message
      (blue_plus_on_red_five_rejected : bool)
        (green_skip_on_red_five_rejected : bool)];
  [%expect
    {|
    ((blue_plus_on_red_five_rejected true)
     (green_skip_on_red_five_rejected true))
    |}]
;;

(* official 2-player rule: reverse acts like a skip, so the player who played
   it goes again; with 3+ players it only flips the direction *)
let%expect_test "reverse skips the opponent in a two-player game" =
  let rev = { Card.color = Red; value = Reverse; id = 830 } in
  let f = { Card.color = Green; value = Zero; id = 831 } in
  let top = { Card.color = Red; value = Five; id = 832 } in
  let two_player =
    Game_state.for_testing
      ~player_hands:[ "a", [ rev; f ]; "b", [] ]
      ~top_card:top
      ~draw_pile:[]
      ~pending_draws:0
      ~turn:0
  in
  let t =
    Rule_engine.apply_action
      Rule_engine.Ruleset.default
      two_player
      ~player_id:0
      ~action:(Play { card_id = 830; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  print_s [%message "two players" (t.turn : int) (t.direction : Direction.t)];
  let three_player =
    Game_state.for_testing
      ~player_hands:[ "a", [ rev; f ]; "b", []; "c", [] ]
      ~top_card:top
      ~draw_pile:[]
      ~pending_draws:0
      ~turn:0
  in
  let t =
    Rule_engine.apply_action
      Rule_engine.Ruleset.default
      three_player
      ~player_id:0
      ~action:(Play { card_id = 830; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  print_s
    [%message "three players" (t.turn : int) (t.direction : Direction.t)];
  [%expect
    {|
    ("two players" (t.turn 0) (t.direction Counter))
    ("three players" (t.turn 2) (t.direction Counter))
    |}]
;;

let%expect_test "matching special cards still play" =
  let p2 = { Card.color = Red; value = Plus; id = 810 } in
  let top = { Card.color = Red; value = Five; id = 811 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", [ p2 ]; "b", []; "c", [] ]
      ~top_card:top
      ~draw_pile:(Game_state.create_card_deck ())
      ~pending_draws:0
      ~turn:0
  in
  let t =
    Rule_engine.apply_action
      Rule_engine.Ruleset.default
      t
      ~player_id:0
      ~action:(Play { card_id = 810; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  (* immediate semantics: the victim draws 2 on the spot and is skipped *)
  let victim_hand =
    List.length (Player.get_hand (List.nth_exn t.players 1))
  in
  print_s
    [%message (t.pending_draws : int) (t.turn : int) (victim_hand : int)];
  [%expect {| ((t.pending_draws 0) (t.turn 2) (victim_hand 2)) |}]
;;

(* regression: in the stacking variant a wild (or any non-stacking card)
   cannot dodge a pending penalty - the penalty rule outranks the specials *)
let%expect_test "wild cannot dodge pending draws" =
  let w = { Card.color = NoColor; value = Wild; id = 820 } in
  let f = { Card.color = Red; value = Zero; id = 821 } in
  let top = { Card.color = Green; value = Plus; id = 822 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", [ w; f ]; "b", [] ]
      ~top_card:top
      ~draw_pile:(Game_state.create_card_deck ())
      ~pending_draws:2
      ~turn:0
  in
  let t =
    Rule_engine.apply_action
      Rule_engine.Ruleset.stacking_variant
      t
      ~player_id:0
      ~action:(Play { card_id = 820; declared_color = Some Red; swap_with = None })
    |> Or_error.ok_exn
  in
  let hand = List.length (Player.get_hand (List.nth_exn t.players 0)) in
  let top_unchanged = Card.equal t.top_card top in
  (* wild not played: hand went 2 -> 4 (penalty), turn passed, pending
     cleared *)
  print_s
    [%message
      (hand : int)
        (t.pending_draws : int)
        (t.turn : int)
        (top_unchanged : bool)];
  [%expect
    {|
    ((hand 4) (t.pending_draws 0) (t.turn 1) (top_unchanged true))
    |}]
;;

(* A game that opens on a flipped wild has no colour in force, so the first
   player leads with whatever they like - including specials. *)
let%expect_test "any card opens the game on a flipped wild" =
  let wild_top = { Card.color = NoColor; value = Wild; id = 990 } in
  let candidates =
    [ { Card.color = Red; value = Seven; id = 991 }
    ; { Card.color = Blue; value = Skip; id = 992 }
    ; { Card.color = Green; value = Plus; id = 993 }
    ; { Card.color = NoColor; value = Wild4; id = 994 }
    ]
  in
  List.iter candidates ~f:(fun (card : Card.t) ->
    let t =
      Game_state.for_testing
        ~player_hands:[ "a", [ card ]; "b", [] ]
        ~top_card:wild_top
        ~draw_pile:(Game_state.create_card_deck ())
        ~pending_draws:0
        ~turn:0
    in
    let declared_color =
      match card.value with Wild | Wild4 -> Some Card.Color.Red | _ -> None
    in
    let result =
      Rule_engine.apply_action
        Rule_engine.Ruleset.default
        t
        ~player_id:0
        ~action:(Play { card_id = card.id; declared_color; swap_with = None })
    in
    let value = card.value in
    let accepted = Or_error.is_ok result in
    print_s [%message (value : Card.Value.t) (accepted : bool)]);
  (* once a real colour is in force the usual matching rules apply again *)
  let red_top = { Card.color = Red; value = Three; id = 995 } in
  let mismatch = { Card.color = Blue; value = Seven; id = 996 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", [ mismatch ]; "b", [] ]
      ~top_card:red_top
      ~draw_pile:(Game_state.create_card_deck ())
      ~pending_draws:0
      ~turn:0
  in
  let rejected =
    Or_error.is_error
      (Rule_engine.apply_action
         Rule_engine.Ruleset.default
         t
         ~player_id:0
         ~action:(Play { card_id = 996; declared_color = None; swap_with = None }))
  in
  print_s [%message "blue seven on a red three" (rejected : bool)];
  [%expect
    {|
    ((value Seven) (accepted true))
    ((value Skip) (accepted true))
    ((value Plus) (accepted true))
    ((value Wild4) (accepted true))
    ("blue seven on a red three" (rejected true))
    |}]
;;

(* ---------- multi-winner play (play until ...) ---------- *)

(* four seats; "a" is one card from going out, the rest hold two each *)
let finish_setup text =
  let rules = Rule_parser.parse_ruleset text |> Or_error.ok_exn in
  let top = { Card.color = Red; value = Five; id = 700 } in
  let c n v = { Card.color = Card.Color.Red; value = v; id = n } in
  let t =
    Game_state.for_testing
      ~player_hands:
        [ "a", [ c 701 One ]
        ; "b", [ c 702 Two; c 712 Six ]
        ; "c", [ c 703 Three; c 713 Seven ]
        ; "d", [ c 704 Four; c 714 Eight ]
        ]
      ~top_card:top
      ~draw_pile:(Game_state.create_card_deck ())
      ~pending_draws:0
      ~turn:0
  in
  rules, t
;;

let play rules t ~player_id ~card_id =
  Rule_engine.apply_action
    rules
    t
    ~player_id
    ~action:(Play { card_id; declared_color = None; swap_with = None })
  |> Or_error.ok_exn
;;

let%expect_test "by default the first player out ends the game" =
  let rules, t = finish_setup "use standard" in
  let t = play rules t ~player_id:0 ~card_id:701 in
  print_s [%message (t.winner : int option) (t.finished : int list)];
  [%expect {| ((t.winner (0)) (t.finished (0))) |}]
;;

(* the whole point: going out no longer stops everyone else *)
let%expect_test "play until one player is left keeps the game going" =
  let rules, t = finish_setup "play until one player is left\nuse standard" in
  let t = play rules t ~player_id:0 ~card_id:701 in
  print_s
    [%message "a is out" (t.winner : int option) (t.finished : int list) (t.turn : int)];
  (* b, c and d each play once; the rotation must step over the empty seat *)
  let t = play rules t ~player_id:1 ~card_id:702 in
  let t = play rules t ~player_id:2 ~card_id:703 in
  let t = play rules t ~player_id:3 ~card_id:704 in
  print_s [%message "one lap later" (t.turn : int)];
  (* b goes out second, which leaves only c and d -> still not over *)
  let t = play rules t ~player_id:1 ~card_id:712 in
  print_s [%message "b is out" (t.winner : int option) (t.finished : int list)];
  let t = play rules t ~player_id:2 ~card_id:713 in
  print_s
    [%message "c is out - game over" (t.winner : int option) (t.finished : int list)];
  [%expect
    {|
    ("a is out" (t.winner ()) (t.finished (0)) (t.turn 1))
    ("one lap later" (t.turn 1))
    ("b is out" (t.winner ()) (t.finished (0 1)))
    ("c is out - game over" (t.winner (0)) (t.finished (0 1 2)))
    |}]
;;

let%expect_test "play until N players finish stops at N" =
  let rules, t = finish_setup "play until 2 players finish\nuse standard" in
  let t = play rules t ~player_id:0 ~card_id:701 in
  print_s [%message "one out" (t.winner : int option)];
  let t = play rules t ~player_id:1 ~card_id:702 in
  let t = play rules t ~player_id:2 ~card_id:703 in
  let t = play rules t ~player_id:3 ~card_id:704 in
  let t = play rules t ~player_id:1 ~card_id:712 in
  print_s [%message "two out" (t.winner : int option) (t.finished : int list)];
  [%expect
    {|
    ("one out" (t.winner ()))
    ("two out" (t.winner (0)) (t.finished (0 1)))
    |}]
;;

(* nobody can take the last place from themselves, so an over-large N must
   still be reachable rather than hanging the table forever *)
let%expect_test "play until N is clamped to one short of the table" =
  print_s
    [%message
      (Game_state.Finish.needed (After 5) ~num_players:3 : int)
        (Game_state.Finish.needed Last_standing ~num_players:4 : int)
        (Game_state.Finish.needed First_out ~num_players:4 : int)];
  [%expect
    {|
    (("Game_state.Finish.needed (After 5) ~num_players:3" 2)
     ("Game_state.Finish.needed Last_standing ~num_players:4" 3)
     ("Game_state.Finish.needed First_out ~num_players:4" 1))
    |}]
;;

let%expect_test "play until parses in any position and rejects nonsense" =
  let finish_of text =
    match Rule_parser.parse_ruleset text with
    | Error e -> Error (Error.to_string_hum e)
    | Ok rules ->
      Ok
        (List.find_map rules ~f:(fun (r : Rule.t) ->
           List.find_map r.actions ~f:(function
             | Game_state.Effect.CheckWinner f -> Some f
             | _ -> None)))
  in
  let show label text =
    print_s
      [%message label ~_:(finish_of text : (Game_state.Finish.t option, string) Result.t)]
  in
  show "before use" "play until 2 players finish\nuse standard";
  show "after use" "use standard\nplay until one player is left";
  show "twice" "play until 2 players finish\nplay until 3 players finish\nuse standard";
  show "nonsense" "use standard\nplay until bananas";
  [%expect
    {|
    ("before use" (Ok ((After 2))))
    ("after use" (Ok (Last_standing)))
    (twice (Error "line 2: 'play until' given more than once"))
    (nonsense
     (Error
      "line 2: expected 'play until N players finish', 'play until one player is left', or 'play until first player finishes'"))
    |}]
;;

(* ---------- jumping in (playing out of turn) ---------- *)

(* seats a b c d, a red seven on the pile, and d holding its twin. The turn
   starts on b, so a jump from d has to skip b and c. *)
let jump_setup ~turn =
  let top = { Card.color = Red; value = Seven; id = 800 } in
  let twin = { Card.color = Red; value = Seven; id = 801 } in
  let filler n = { Card.color = Blue; value = Two; id = 810 + n } in
  ( top
  , Game_state.for_testing
      ~player_hands:
        [ "a", [ filler 0 ]
        ; "b", [ filler 1 ]
        ; "c", [ filler 2 ]
        ; "d", [ twin; filler 3 ]
        ]
      ~top_card:top
      ~draw_pile:(Game_state.create_card_deck ())
      ~pending_draws:0
      ~turn )
;;

let jump_rules = Rule_engine.Ruleset.jump_in_variant

let%expect_test "an exact match plays out of turn and skips the seats between" =
  let _top, t = jump_setup ~turn:1 in
  let t =
    Rule_engine.apply_action
      jump_rules
      t
      ~player_id:3
      ~action:(Play { card_id = 801; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  (* the turn leapt to d and then advanced, so play resumes at a *)
  let jumper_hand = List.length (Player.get_hand (List.nth_exn t.players 3)) in
  print_s
    [%message
      (t.turn : int) (jumper_hand : int) (t.current_color : Card.Color.t)];
  [%expect {| ((t.turn 0) (jumper_hand 1) (t.current_color Red)) |}]
;;

let%expect_test "jumping in needs the exact card, and the rule to allow it" =
  let _top, t = jump_setup ~turn:1 in
  (* c holds a blue two: not an exact match, so still out of turn *)
  let wrong_card =
    Rule_engine.apply_action
      jump_rules
      t
      ~player_id:2
      ~action:(Play { card_id = 812; declared_color = None; swap_with = None })
  in
  (* the same jump under a ruleset without the rule *)
  let no_rule =
    Rule_engine.apply_action
      Rule_engine.Ruleset.default
      t
      ~player_id:3
      ~action:(Play { card_id = 801; declared_color = None; swap_with = None })
  in
  print_s
    [%message
      (Or_error.is_error wrong_card : bool) (Or_error.is_error no_rule : bool)];
  [%expect
    {|
    (("Or_error.is_error wrong_card" true) ("Or_error.is_error no_rule" true))
    |}]
;;

(* the current player's own exact match is an ordinary play, not a jump: the
   turn must still move on by one rather than staying put *)
let%expect_test "the current player is unaffected by the jump-in rule" =
  let _top, t = jump_setup ~turn:3 in
  let t =
    Rule_engine.apply_action
      jump_rules
      t
      ~player_id:3
      ~action:(Play { card_id = 801; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  print_s [%message (t.turn : int)];
  [%expect {| (t.turn 0) |}]
;;

(* wilds have no printed colour or number; letting one match "exactly" would
   set the active colour to NoColor and make everything playable *)
let%expect_test "a wild never counts as an exact match" =
  let wild_top = { Card.color = NoColor; value = Wild; id = 820 } in
  let other_wild = { Card.color = NoColor; value = Wild; id = 821 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", []; "b", []; "c", [ other_wild ] ]
      ~top_card:wild_top
      ~draw_pile:(Game_state.create_card_deck ())
      ~pending_draws:0
      ~turn:0
  in
  let rejected =
    Or_error.is_error
      (Rule_engine.apply_action
         jump_rules
         t
         ~player_id:2
         ~action:(Play { card_id = 821; declared_color = Some Red; swap_with = None }))
  in
  print_s [%message "wild jumped onto a wild" (rejected : bool)];
  [%expect {| ("wild jumped onto a wild" (rejected true)) |}]
;;

(* the UI highlights whatever this returns, so it must include a jump-in
   while it is somebody else's turn - and nothing at all without the rule *)
let%expect_test "playable ids expose an out-of-turn jump" =
  let _top, t = jump_setup ~turn:1 in
  let with_rule =
    Rule_engine.playable_card_ids jump_rules t ~player_id:3
  in
  let without_rule =
    Rule_engine.playable_card_ids Rule_engine.Ruleset.default t ~player_id:3
  in
  print_s [%message (with_rule : int list) (without_rule : int list)];
  [%expect {| ((with_rule (801)) (without_rule ())) |}]
;;

(* ---------- the UNO button ---------- *)

(* Three players. "a" is one card away from UNO and holds a spare so that
   playing does not win outright. "b" and "c" hold two cards each: a player
   sitting on an empty hand would hit exactly one card the moment they drew
   and become catchable themselves, which is real behaviour but not what
   these tests are about. *)
let uno_setup () =
  let playable = { Card.color = Red; value = Seven; id = 940 } in
  let spare = { Card.color = Blue; value = Two; id = 941 } in
  let top = { Card.color = Red; value = Three; id = 942 } in
  let filler n = { Card.color = Green; value = Four; id = 943 + n } in
  Game_state.for_testing
    ~player_hands:
      [ "a", [ playable; spare ]
      ; "b", [ filler 0; filler 1 ]
      ; "c", [ filler 2; filler 3 ]
      ]
    ~top_card:top
    ~draw_pile:(Game_state.create_card_deck ())
    ~pending_draws:0
    ~turn:0
;;

let rules = Rule_engine.Ruleset.default

let hand_of (t : Game_state.t) id =
  List.length (Player.get_hand (List.nth_exn t.players id))
;;

(* playing down to one card opens the window on the player who did it *)
let%expect_test "playing to one card makes you catchable" =
  let t = uno_setup () in
  print_s [%message "before" (t.uno_vulnerable : int option)];
  let t =
    Rule_engine.apply_action
      rules
      t
      ~player_id:0
      ~action:(Play { card_id = 940; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  print_s
    [%message "after playing" (t.uno_vulnerable : int option) (t.turn : int)];
  [%expect
    {|
    (before (t.uno_vulnerable ()))
    ("after playing" (t.uno_vulnerable (0)) (t.turn 1))
    |}]
;;

let%expect_test "calling your own UNO closes the window and costs nothing" =
  let t = uno_setup () in
  let t =
    Rule_engine.apply_action
      rules
      t
      ~player_id:0
      ~action:(Play { card_id = 940; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  let t =
    Rule_engine.apply_action rules t ~player_id:0 ~action:Call_uno
    |> Or_error.ok_exn
  in
  (* an UNO press is not a turn: it must not move play along *)
  let hand = hand_of t 0 in
  print_s
    [%message (t.uno_vulnerable : int option) (hand : int) (t.turn : int)];
  [%expect {| ((t.uno_vulnerable ()) (hand 1) (t.turn 1)) |}]
;;

let%expect_test "catching a silent player costs them the penalty" =
  let t = uno_setup () in
  let t =
    Rule_engine.apply_action
      rules
      t
      ~player_id:0
      ~action:(Play { card_id = 940; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  (* "b" pounces before "a" says anything *)
  let t =
    Rule_engine.apply_action rules t ~player_id:1 ~action:Call_uno
    |> Or_error.ok_exn
  in
  let victim = hand_of t 0 in
  let catcher = hand_of t 1 in
  print_s
    [%message (victim : int) (catcher : int) (t.uno_vulnerable : int option)];
  (* the catch is spent: a second pounce is now a false call and stings *)
  let t =
    Rule_engine.apply_action rules t ~player_id:2 ~action:Call_uno
    |> Or_error.ok_exn
  in
  let caller = hand_of t 2 in
  print_s [%message "second catch" (caller : int)];
  [%expect
    {|
    ((victim 3) (catcher 2) (t.uno_vulnerable ()))
    ("second catch" (caller 4))
    |}]
;;

let%expect_test "calling UNO with nothing to claim costs you cards" =
  let t = uno_setup () in
  let t =
    Rule_engine.apply_action rules t ~player_id:1 ~action:Call_uno
    |> Or_error.ok_exn
  in
  let caller = hand_of t 1 in
  print_s [%message (caller : int) (t.turn : int)];
  [%expect {| ((caller 4) (t.turn 0)) |}]
;;

(* the window shuts as soon as somebody else takes a real turn *)
let%expect_test "the catch window closes when the next player acts" =
  let t = uno_setup () in
  let t =
    Rule_engine.apply_action
      rules
      t
      ~player_id:0
      ~action:(Play { card_id = 940; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  let t =
    Rule_engine.apply_action rules t ~player_id:1 ~action:Draw
    |> Or_error.ok_exn
  in
  print_s [%message "after b draws" (t.uno_vulnerable : int option)];
  (* too late: "c" pressing now is a false call, and "a" keeps her one card *)
  let t =
    Rule_engine.apply_action rules t ~player_id:2 ~action:Call_uno
    |> Or_error.ok_exn
  in
  let a = hand_of t 0 in
  let c = hand_of t 2 in
  print_s [%message "late catch" (a : int) (c : int)];
  [%expect
    {|
    ("after b draws" (t.uno_vulnerable ()))
    ("late catch" (a 1) (c 4))
    |}]
;;

(* a player whose window already closed is not fined for pressing late -
   "has uno" asks how many cards you hold, not whether you are catchable *)
let%expect_test "calling UNO late is harmless while you still hold one card" =
  let t = uno_setup () in
  let t =
    Rule_engine.apply_action
      rules
      t
      ~player_id:0
      ~action:(Play { card_id = 940; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  let t =
    Rule_engine.apply_action rules t ~player_id:1 ~action:Draw
    |> Or_error.ok_exn
  in
  let t =
    Rule_engine.apply_action rules t ~player_id:0 ~action:Call_uno
    |> Or_error.ok_exn
  in
  let a = hand_of t 0 in
  print_s [%message (a : int)];
  [%expect {| (a 1) |}]
;;

(* winning must not leave a phantom catch open on the winner *)
let%expect_test "playing your last card wins instead of exposing you" =
  let last = { Card.color = Red; value = Seven; id = 950 } in
  let top = { Card.color = Red; value = Three; id = 951 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", [ last ]; "b", []; "c", [] ]
      ~top_card:top
      ~draw_pile:(Game_state.create_card_deck ())
      ~pending_draws:0
      ~turn:0
  in
  let t =
    Rule_engine.apply_action
      rules
      t
      ~player_id:0
      ~action:(Play { card_id = 950; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  print_s [%message (t.winner : int option) (t.uno_vulnerable : int option)];
  [%expect {| ((t.winner (0)) (t.uno_vulnerable ())) |}]
;;

(* ---------- rule parser: round-trips against the hand-coded rulesets ---------- *)
(* ids are auto-assigned by the parser and hand-picked in the hand-coded
   rules, so compare everything else *)
let strip_ids (rules : Rule.t list) =
  List.map rules ~f:(fun (r : Rule.t) -> { r with id = 0 })
;;

let check_against_hand_coded text expected =
  match Rule_parser.parse_ruleset text with
  | Error e -> print_s [%message "parse error" (e : Error.t)]
  | Ok parsed ->
    if [%equal: Rule.t list] (strip_ids parsed) (strip_ids expected)
    then print_endline "parsed rules match the hand-coded ruleset"
    else
      print_s
        [%message "MISMATCH" (parsed : Rule.t list) (expected : Rule.t list)]
;;

(* the canonical preset texts (lib/presets.ml) must parse to exactly the
   hand-coded variants - they are what the lobby toggles and `use` expand *)
let%expect_test "parsed default ruleset equals hand-coded default" =
  check_against_hand_coded Presets.standard_text Rule_engine.Ruleset.default;
  [%expect {| parsed rules match the hand-coded ruleset |}]
;;

let%expect_test "parsed draw-until ruleset equals hand-coded variant" =
  check_against_hand_coded
    Presets.draw_until_text
    Rule_engine.Ruleset.draw_until_variant;
  [%expect {| parsed rules match the hand-coded ruleset |}]
;;

let%expect_test "parsed stacking ruleset equals hand-coded variant" =
  check_against_hand_coded
    Presets.stacking_text
    Rule_engine.Ruleset.stacking_variant;
  [%expect {| parsed rules match the hand-coded ruleset |}]
;;

let%expect_test "parsed combined ruleset equals hand-coded variant" =
  check_against_hand_coded
    Presets.stacking_draw_until_text
    Rule_engine.Ruleset.stacking_draw_until_variant;
  [%expect {| parsed rules match the hand-coded ruleset |}]
;;

(* jump-in composes onto each of the four bases *)
let%expect_test "parsed jump-in rulesets equal their hand-coded variants" =
  check_against_hand_coded Presets.jump_in_text Rule_engine.Ruleset.jump_in_variant;
  check_against_hand_coded
    Presets.stacking_jump_in_text
    Rule_engine.Ruleset.stacking_jump_in_variant;
  check_against_hand_coded
    Presets.draw_until_jump_in_text
    Rule_engine.Ruleset.draw_until_jump_in_variant;
  check_against_hand_coded
    Presets.stacking_draw_until_jump_in_text
    Rule_engine.Ruleset.stacking_draw_until_jump_in_variant;
  [%expect
    {|
    parsed rules match the hand-coded ruleset
    parsed rules match the hand-coded ruleset
    parsed rules match the hand-coded ruleset
    parsed rules match the hand-coded ruleset
    |}]
;;

(* `use <preset>` expands to the same rules as pasting the preset text *)
let%expect_test "use expands presets, combines, extends, and overrides" =
  let count text =
    match Rule_parser.parse_ruleset text with
    | Ok rules -> print_s [%message (List.length rules : int)]
    | Error e -> print_s [%message "parse error" (e : Error.t)]
  in
  (match Rule_parser.parse_ruleset "use stacking" with
   | Error e -> print_s [%message "parse error" (e : Error.t)]
   | Ok rules ->
     print_s
       [%message
         "use stacking = stacking preset"
           ([%equal: Rule.t list]
              (strip_ids rules)
              (strip_ids Rule_engine.Ruleset.stacking_variant)
            : bool)]);
  (* extension: preset rules plus one custom rule *)
  count
    {|use stacking
rule "sevens are wild" priority 115:
  when card is plus four and your turn
  do play the card, set color to declared, advance turn|};
  (* override: redefining a preset rule by name replaces it *)
  count
    {|use stacking
rule "pass on stack" priority 120:
  when player passes and your turn and stack is open
  do clear stack, skip next player|};
  (match Rule_parser.parse_ruleset "use nonsense mode" with
   | Ok _ -> print_endline "unexpectedly parsed"
   | Error e -> print_s [%message (e : Error.t)]);
  [%expect
    {|
    ("use stacking = stacking preset"
     ( "([%equal : Rule.t list]) (strip_ids rules)\
      \n  (strip_ids Rule_engine.Ruleset.stacking_variant)" true))
    ("List.length rules" 15)
    ("List.length rules" 14)
    (e
     "line 1: unknown preset 'nonsense mode' after 'use' (available: standard, stacking, draw until playable, stacking with draw until playable, jump in, stacking with jump in, draw until playable with jump in, stacking with draw until playable with jump in, seven zero)")
    |}]
;;

(* stacking + draw-until combined: when stuck you draw one card per click
   (turn stays), you cannot draw mid-stack, and chaining still works *)
let%expect_test "combined stacking and draw-until variant plays a turn" =
  let rules =
    Rule_parser.parse_ruleset "use stacking with draw until playable"
    |> Or_error.ok_exn
  in
  let s1 = { Card.color = Red; value = Seven; id = 720 } in
  let s2 = { Card.color = Blue; value = Seven; id = 721 } in
  let top = { Card.color = Red; value = Three; id = 722 } in
  let filler = { Card.color = Green; value = Zero; id = 723 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", [ s1; s2 ]; "b", [] ]
      ~top_card:top
      ~draw_pile:[ filler ]
      ~pending_draws:0
      ~turn:0
  in
  (* drawing with the stack closed takes one card and keeps the turn *)
  let t = Rule_engine.apply_action rules t ~player_id:0 ~action:Draw |> Or_error.ok_exn in
  print_s
    [%message
      "after draw"
        (t.turn : int)
        (List.length (Player.get_hand (List.nth_exn t.players 0)) : int)];
  (* open and continue a stack *)
  let t =
    Rule_engine.apply_action rules t ~player_id:0
      ~action:(Play { card_id = 720; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  let mid_stack_draw = Rule_engine.apply_action rules t ~player_id:0 ~action:Draw in
  print_s
    [%message
      "mid-stack" (t.stacking_value : Card.Value.t option)
        (Or_error.is_error mid_stack_draw : bool)];
  let t =
    Rule_engine.apply_action rules t ~player_id:0
      ~action:(Play { card_id = 721; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  (* nothing left to continue: pass is the only move (the server auto-passes) *)
  print_s
    [%message
      (Rule_engine.only_pass_available rules t : bool)];
  let t = Rule_engine.apply_action rules t ~player_id:0 ~action:Pass |> Or_error.ok_exn in
  print_s [%message "after pass" (t.turn : int) (t.stacking_value : Card.Value.t option)];
  [%expect
    {|
    ("after draw" (t.turn 0)
     ("List.length (Player.get_hand (List.nth_exn t.players 0))" 3))
    (mid-stack (t.stacking_value (Seven))
     ("Or_error.is_error mid_stack_draw" true))
    ("Rule_engine.only_pass_available rules t" true)
    ("after pass" (t.turn 1) (t.stacking_value ()))
    |}]
;;

(* custom rules layered on a preset must actually fire in gameplay: an
   override (same name) replaces the preset's behavior *)
let%expect_test "custom override on a preset changes gameplay" =
  let rules =
    Rule_parser.parse_ruleset
      {|use standard
rule "play matching card" priority 10:
  when (card matches color or card matches value) and your turn
  do play the card, set color from card, next player draws 1 cards, advance turn|}
    |> Or_error.ok_exn
  in
  let mine = { Card.color = Red; value = Nine; id = 730 } in
  let top = { Card.color = Red; value = Five; id = 731 } in
  let burn = { Card.color = Blue; value = Two; id = 732 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", [ mine ]; "b", []; "c", [] ]
      ~top_card:top
      ~draw_pile:[ burn ]
      ~pending_draws:0
      ~turn:0
  in
  let t =
    Rule_engine.apply_action rules t ~player_id:0
      ~action:(Play { card_id = 730; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  print_s
    [%message
      "matching card burned the neighbor"
        (t.turn : int)
        (List.length (Player.get_hand (List.nth_exn t.players 1)) : int)];
  [%expect
    {|
    ("matching card burned the neighbor" (t.turn 1)
     ("List.length (Player.get_hand (List.nth_exn t.players 1))" 1))
    |}]
;;

(* a new custom rule at higher priority shadows a preset special *)
let%expect_test "custom high-priority rule beats a preset special" =
  let rules =
    Rule_parser.parse_ruleset
      {|use standard
rule "reverse is just a card" priority 115:
  when card is reverse and (card matches color or card matches value) and your turn
  do play the card, set color from card, advance turn|}
    |> Or_error.ok_exn
  in
  let rev = { Card.color = Red; value = Reverse; id = 740 } in
  let top = { Card.color = Red; value = Five; id = 741 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", [ rev ]; "b", []; "c", [] ]
      ~top_card:top
      ~draw_pile:[]
      ~pending_draws:0
      ~turn:0
  in
  let t =
    Rule_engine.apply_action rules t ~player_id:0
      ~action:(Play { card_id = 740; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  print_s
    [%message
      "reverse played plainly" (t.turn : int) (t.direction : Direction.t)];
  [%expect {| ("reverse played plainly" (t.turn 1) (t.direction Clockwise)) |}]
;;

(* overrides work on the combined preset too *)
let%expect_test "custom wild override in the combined variant" =
  let rules =
    Rule_parser.parse_ruleset
      {|use stacking with draw until playable
rule "play wild" priority 100:
  when card is wild and your turn and not stack is open
  do play the card, set color to declared, skip next player|}
    |> Or_error.ok_exn
  in
  let wild = { Card.color = NoColor; value = Wild; id = 750 } in
  let top = { Card.color = Red; value = Five; id = 751 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", [ wild ]; "b", []; "c", [] ]
      ~top_card:top
      ~draw_pile:[]
      ~pending_draws:0
      ~turn:0
  in
  let t =
    Rule_engine.apply_action rules t ~player_id:0
      ~action:(Play { card_id = 750; declared_color = Some Blue; swap_with = None })
    |> Or_error.ok_exn
  in
  print_s
    [%message
      "wild now skips" (t.turn : int) (t.current_color : Card.Color.t)];
  [%expect {| ("wild now skips" (t.turn 2) (t.current_color Blue)) |}]
;;

let%expect_test "parsed stacking ruleset plays a real stacking turn" =
  let rules = Rule_parser.parse_ruleset Presets.stacking_text |> Or_error.ok_exn in
  let s1 = { Card.color = Red; value = Seven; id = 700 } in
  let s2 = { Card.color = Blue; value = Seven; id = 701 } in
  let top = { Card.color = Red; value = Three; id = 702 } in
  let f = { Card.color = Green; value = Zero; id = 703 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", [ s1; s2; f ]; "b", [] ]
      ~top_card:top
      ~draw_pile:(Game_state.create_card_deck ())
      ~pending_draws:0
      ~turn:0
  in
  let t =
    Rule_engine.apply_action
      rules
      t
      ~player_id:0
      ~action:(Play { card_id = 700; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  let t =
    Rule_engine.apply_action
      rules
      t
      ~player_id:0
      ~action:(Play { card_id = 701; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  let t =
    Rule_engine.apply_action rules t ~player_id:0 ~action:Pass
    |> Or_error.ok_exn
  in
  print_s
    [%message
      (t.turn : int)
        (t.stacking_value : Card.Value.t option)
        (List.length (Player.get_hand (List.nth_exn t.players 0)) : int)];
  [%expect
    {|
    ((t.turn 1) (t.stacking_value ())
     ("List.length (Player.get_hand (List.nth_exn t.players 0))" 1))
    |}]
;;

let%expect_test "parser defaults priority and assigns ids in order" =
  let rules =
    Rule_parser.parse_ruleset
      {|rule "first": when always do advance turn
        rule "second": when always do advance turn|}
    |> Or_error.ok_exn
  in
  print_s [%message (rules : Rule.t list)];
  [%expect
    {|
    (rules
     (((id 1) (priority 50) (condition Always) (actions (AdvanceTurn)))
      ((id 2) (priority 50) (condition Always) (actions (AdvanceTurn)))))
    |}]
;;

let%expect_test "parse errors carry line numbers and the rule name" =
  (match
     Rule_parser.parse_ruleset
       {|rule "confused":
  when card is purple
  do advance turn|}
   with
   | Ok _ -> print_endline "unexpectedly parsed"
   | Error e -> print_s [%message (e : Error.t)]);
  (match
     Rule_parser.parse_ruleset
       {|rule "flying":
  when always
  do fly to the moon|}
   with
   | Ok _ -> print_endline "unexpectedly parsed"
   | Error e -> print_s [%message (e : Error.t)]);
  [%expect
    {|
    (e ("in rule \"confused\"" "unknown condition (line 2 at 'card')"))
    (e ("in rule \"flying\"" "unknown effect (line 3 at 'fly')"))
    |}]
;;
(* the checker warns about the two easy override mistakes: a card-play rule
   that never plays the card, and one that never ends the turn. The presets
   themselves must stay warning-free. *)
let%expect_test "lint flags card-play rules missing play-the-card or advance-turn" =
  let check text =
    match Rule_parser.parse_ruleset_checked text with
    | Error e -> print_s [%message (e : Error.t)]
    | Ok (_, warnings) -> print_s [%message (warnings : Rule_parser.Lint.t list)]
  in
  check
    {|use standard
rule "red reverse" priority 115:
  when card is reverse and your turn
  do set color to red|};
  check
    {|use standard
rule "play reverse" priority 100:
  when card is reverse and (card matches color or card matches value) and your turn
  do play the card, set color to red|};
  [%expect
    {|
    (warnings
     (((rule_name "red reverse") (kind Missing_play)
       (message
        "rule \"red reverse\" fires when a card is played but has no 'play the card' effect - the card will stay in the hand")
       (fix ("play the card")))))
    (warnings
     (((rule_name "play reverse") (kind Missing_advance)
       (message
        "rule \"play reverse\" plays the card but has no 'advance turn' effect - the turn will never end")
       (fix ("advance turn")))))
    |}]
;;

let%expect_test "presets and mid-stack rules produce no lint warnings" =
  (* every preset, so new ones (jump-in, uno rules) stay warning-free too *)
  List.iter
    (List.map Presets.all ~f:fst)
    ~f:(fun preset ->
      match Rule_parser.parse_ruleset_checked ("use " ^ preset) with
      | Error e -> print_s [%message preset (e : Error.t)]
      | Ok (_, warnings) -> print_s [%message preset (warnings : Rule_parser.Lint.t list)]);
  [%expect
    {|
    (standard (warnings ()))
    (stacking (warnings ()))
    ("draw until playable" (warnings ()))
    ("stacking with draw until playable" (warnings ()))
    ("jump in" (warnings ()))
    ("stacking with jump in" (warnings ()))
    ("draw until playable with jump in" (warnings ()))
    ("stacking with draw until playable with jump in" (warnings ()))
    ("seven zero" (warnings ()))
    |}]
;;

(* "close stack" and the historical "clear stack" are the same effect *)
let%expect_test "close stack parses as clear stack" =
  let parse text = Rule_parser.parse_ruleset text |> Or_error.ok_exn in
  let close =
    parse {|rule "pass on stack": when player passes do close stack, advance turn|}
  in
  let clear =
    parse {|rule "pass on stack": when player passes do clear stack, advance turn|}
  in
  print_s [%message (Rule_engine.Ruleset.equal close clear : bool)];
  [%expect {| ("Rule_engine.Ruleset.equal close clear" true) |}]
;;

(* ties are broken by definition order - explicitly, via ids, not sort
   stability. Pinned so a refactor cannot silently flip which rule wins. *)
let%expect_test "equal-priority ties go to the rule defined first" =
  let color_after text =
    let rules = Rule_parser.parse_ruleset text |> Or_error.ok_exn in
    let rev = { Card.color = Green; value = Reverse; id = 960 } in
    let top = { Card.color = Green; value = Five; id = 961 } in
    let t =
      Game_state.for_testing
        ~player_hands:[ "a", [ rev ]; "b", []; "c", [] ]
        ~top_card:top
        ~draw_pile:[]
        ~pending_draws:0
        ~turn:0
    in
    let t =
      Rule_engine.apply_action rules t ~player_id:0
        ~action:(Play { card_id = 960; declared_color = None; swap_with = None })
      |> Or_error.ok_exn
    in
    t.current_color
  in
  let red_first =
    color_after
      {|rule "a": when card is reverse and your turn do play the card, set color to red, advance turn
rule "b": when card is reverse and your turn do play the card, set color to blue, advance turn|}
  in
  let blue_first =
    color_after
      {|rule "b": when card is reverse and your turn do play the card, set color to blue, advance turn
rule "a": when card is reverse and your turn do play the card, set color to red, advance turn|}
  in
  (* and a same-priority custom rule loses its tie against a preset special,
     because `use` expands at the top of the text *)
  let vs_preset =
    color_after
      {|use standard
rule "my red reverse" priority 100:
  when card is reverse and your turn
  do play the card, set color to red, reverse direction, advance turn|}
  in
  print_s
    [%message
      (red_first : Card.Color.t)
        (blue_first : Card.Color.t)
        (vs_preset : Card.Color.t)];
  [%expect {| ((red_first Red) (blue_first Blue) (vs_preset Green)) |}]
;;

(* the checker calls out a rule that can never fire because an identical
   condition always beats it - by priority or by definition order *)
let%expect_test "lint flags dead rules with identical conditions" =
  let check text =
    match Rule_parser.parse_ruleset_checked text with
    | Error e -> print_s [%message (e : Error.t)]
    | Ok (_, warnings) ->
      print_s
        [%message (List.map warnings ~f:(fun w -> w.Rule_parser.Lint.message) : string list)]
  in
  (* same priority: the later twin is dead *)
  check
    {|rule "a": when card is reverse and your turn do play the card, set color to red, advance turn
rule "b": when card is reverse and your turn do play the card, set color to blue, advance turn|};
  (* higher priority elsewhere: the weaker twin is dead regardless of order *)
  check
    {|rule "weak" priority 10: when player passes and your turn do advance turn
rule "strong" priority 90: when player passes and your turn do advance turn|};
  [%expect
    {|
    ("List.map warnings ~f:(fun w -> w.Rule_parser.Lint.message)"
     ("rule \"b\" can never fire - rule \"a\" has the same condition and always wins (higher priority first; a tie goes to the rule defined first)"))
    ("List.map warnings ~f:(fun w -> w.Rule_parser.Lint.message)"
     ("rule \"weak\" can never fire - rule \"strong\" has the same condition and always wins (higher priority first; a tie goes to the rule defined first)"))
    |}]
;;

(* accounts: login auto-registers, verifies passwords case-insensitively on
   the username, and keeps a per-user library of saved rule modes *)
let%expect_test "accounts login, modes, and snapshot round-trip" =
  let t = Accounts.create ~random_state:(Random.State.make [| 7 |]) () in
  let show label result =
    match result with
    | Error e -> print_s [%message label ~error:(e : Error.t)]
    | Ok (status, user, modes) ->
      print_s
        [%message
          label
            (status : [ `Created | `Logged_in ])
            (user : string)
            (List.map modes ~f:(fun m -> m.Accounts.Mode.name) : string list)]
  in
  show "first login" (Accounts.login t ~username:"Dani" ~password:"hunter2");
  show "same name, different case" (Accounts.login t ~username:"dani" ~password:"hunter2");
  show "wrong password" (Accounts.login t ~username:"dani" ~password:"nope");
  let mode_names r =
    match r with
    | Error e -> Error.to_string_hum e
    | Ok modes ->
      String.concat ~sep:", " (List.map modes ~f:(fun m -> m.Accounts.Mode.name))
  in
  print_endline
    (mode_names
       (Accounts.save_mode t ~username:"dani" ~mode_name:"chaos" ~rules_text:"use stacking"));
  print_endline
    (mode_names
       (Accounts.save_mode t ~username:"dani" ~mode_name:"calm" ~rules_text:"use standard"));
  (* same name replaces in place *)
  print_endline
    (mode_names
       (Accounts.save_mode t ~username:"dani" ~mode_name:"CHAOS" ~rules_text:"use draw until playable"));
  (* the store survives a snapshot round-trip *)
  let t2 =
    Accounts.of_snapshot ~random_state:(Random.State.make [| 8 |]) (Accounts.snapshot t)
  in
  show "login after reload" (Accounts.login t2 ~username:"dani" ~password:"hunter2");
  print_endline (mode_names (Accounts.delete_mode t2 ~username:"dani" ~mode_name:"chaos"));
  print_endline (mode_names (Accounts.delete_mode t2 ~username:"dani" ~mode_name:"chaos"));
  [%expect
    {|
    ("first login" (status Created) (user Dani)
     ("List.map modes ~f:(fun m -> m.Accounts.Mode.name)" ()))
    ("same name, different case" (status Logged_in) (user Dani)
     ("List.map modes ~f:(fun m -> m.Accounts.Mode.name)" ()))
    ("wrong password" (error "Wrong password for that username"))
    chaos
    chaos, calm
    CHAOS, calm
    ("login after reload" (status Logged_in) (user Dani)
     ("List.map modes ~f:(fun m -> m.Accounts.Mode.name)" (CHAOS calm)))
    calm
    No saved mode named "chaos"
    |}]
;;

(* "card is 7" tests only the printed number - no pile match required unless
   the author adds one, so this rule makes any seven playable on anything *)
let%expect_test "card is <number> makes that number special" =
  let rules =
    Rule_parser.parse_ruleset
      {|use standard
rule "sevens are hot" priority 115:
  when card is 7 and your turn
  do play the card, set color to red, advance turn|}
    |> Or_error.ok_exn
  in
  let seven = { Card.color = Blue; value = Seven; id = 760 } in
  let eight = { Card.color = Blue; value = Eight; id = 761 } in
  let top = { Card.color = Yellow; value = Five; id = 762 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", [ seven; eight ]; "b", []; "c", [] ]
      ~top_card:top
      ~draw_pile:[]
      ~pending_draws:0
      ~turn:0
  in
  (* a mismatched non-seven is still illegal *)
  (match
     Rule_engine.apply_action rules t ~player_id:0
       ~action:(Play { card_id = 761; declared_color = None; swap_with = None })
   with
   | Ok _ -> print_endline "unexpectedly legal"
   | Error e -> print_s [%message (e : Error.t)]);
  (* the equally mismatched seven plays and turns the pile red *)
  let t =
    Rule_engine.apply_action rules t ~player_id:0
      ~action:(Play { card_id = 760; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  print_s
    [%message "seven played" (t.turn : int) (t.current_color : Card.Color.t)];
  [%expect
    {|
    (e "Illegal move: no rule allows that right now")
    ("seven played" (t.turn 1) (t.current_color Red))
    |}]
;;

let%expect_test "card is <number> covers 0 and rejects numbers past 9" =
  (match
     Rule_parser.parse_ruleset
       {|rule "zeros":
  when card is 0 and your turn
  do play the card, advance turn|}
   with
   | Ok [ rule ] -> print_s [%message (rule.Rule.condition : Rule.Condition.t)]
   | Ok _ -> print_endline "unexpected rule count"
   | Error e -> print_s [%message (e : Error.t)]);
  (match
     Rule_parser.parse_ruleset
       {|rule "impossible":
  when card is 12 and your turn
  do play the card, advance turn|}
   with
   | Ok _ -> print_endline "unexpectedly parsed"
   | Error e -> print_s [%message (e : Error.t)]);
  [%expect
    {|
    (rule.Rule.condition (And (IsNumber 0) IsPlayerTurn))
    (e
     ("in rule \"impossible\""
      "line 2: 'card is 12' - card numbers go from 0 to 9"))
    |}]
;;

(* "card is blue" tests the printed color, so it can make a whole color
   playable on anything; other colors still follow the normal rules *)
let%expect_test "card is <color> makes blue cards play anywhere" =
  let rules =
    Rule_parser.parse_ruleset
      {|use standard
rule "blue anywhere" priority 60:
  when card is blue and your turn
  do play the card, set color from card, advance turn|}
    |> Or_error.ok_exn
  in
  let blue = { Card.color = Blue; value = Two; id = 770 } in
  let green = { Card.color = Green; value = Two; id = 771 } in
  let top = { Card.color = Red; value = Five; id = 772 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", [ blue; green ]; "b", []; "c", [] ]
      ~top_card:top
      ~draw_pile:[]
      ~pending_draws:0
      ~turn:0
  in
  (* the equally mismatched green card is still illegal *)
  (match
     Rule_engine.apply_action rules t ~player_id:0
       ~action:(Play { card_id = 771; declared_color = None; swap_with = None })
   with
   | Ok _ -> print_endline "unexpectedly legal"
   | Error e -> print_s [%message (e : Error.t)]);
  let t =
    Rule_engine.apply_action rules t ~player_id:0
      ~action:(Play { card_id = 770; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  print_s
    [%message "blue played" (t.turn : int) (t.current_color : Card.Color.t)];
  [%expect
    {|
    (e "Illegal move: no rule allows that right now")
    ("blue played" (t.turn 1) (t.current_color Blue))
    |}]
;;

(* "active color is <c>" reads the table's color to match, not the card *)
let%expect_test "active color condition taxes draws while red is up" =
  let rules =
    Rule_parser.parse_ruleset
      {|use standard
rule "red draw tax" priority 60:
  when player draws and active color is red and your turn
  do draw 2 cards, advance turn|}
    |> Or_error.ok_exn
  in
  let c1 = { Card.color = Blue; value = Two; id = 780 } in
  let c2 = { Card.color = Green; value = Seven; id = 781 } in
  let top = { Card.color = Red; value = Five; id = 782 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", []; "b", [] ]
      ~top_card:top
      ~draw_pile:[ c1; c2 ]
      ~pending_draws:0
      ~turn:0
  in
  let t =
    Rule_engine.apply_action rules t ~player_id:0 ~action:Draw
    |> Or_error.ok_exn
  in
  print_s
    [%message
      "drew under red"
        (List.length (Player.get_hand (List.nth_exn t.players 0)) : int)
        (t.turn : int)];
  [%expect
    {|
    ("drew under red"
     ("List.length (Player.get_hand (List.nth_exn t.players 0))" 2) (t.turn 1))
    |}]
;;

let%expect_test "color conditions parse; bad colors are rejected" =
  (match
     Rule_parser.parse_ruleset
       {|rule "c": when card is yellow and active color is green and your turn do play the card, set color from card, advance turn|}
   with
   | Ok [ rule ] -> print_s [%message (rule.Rule.condition : Rule.Condition.t)]
   | Ok _ -> print_endline "unexpected rule count"
   | Error e -> print_s [%message (e : Error.t)]);
  (match
     Rule_parser.parse_ruleset
       {|rule "bad": when active color is purple do advance turn|}
   with
   | Ok _ -> print_endline "unexpectedly parsed"
   | Error e -> print_s [%message (e : Error.t)]);
  [%expect
    {|
    (rule.Rule.condition
     (And (IsCardColor Yellow) (And (ActiveColorIs Green) IsPlayerTurn)))
    (e
     ("in rule \"bad\""
      "line 1: unknown color 'purple' (expected red, green, blue, or yellow)"))
    |}]
;;

(* playing a card without a color effect leaves the previous color active
   (a blue 0 on red keeps red), except when the condition guarantees the
   card already matches the color; wild rules are pointed at 'set color to
   declared' since a wild has no printed color *)
let%expect_test "lint flags plays that never set the color" =
  let check text =
    match Rule_parser.parse_ruleset_checked text with
    | Error e -> print_s [%message (e : Error.t)]
    | Ok (_, warnings) -> print_s [%message (warnings : Rule_parser.Lint.t list)]
  in
  (* a card-value condition can change the color, so this goes stale *)
  check
    {|use standard
rule "quiet zeros" priority 60:
  when card is 0 and your turn
  do play the card, advance turn|};
  (* guaranteed color match: leaving the color untouched is correct *)
  check
    {|use standard
rule "same color only" priority 60:
  when card matches color and your turn
  do play the card, advance turn|};
  (* wild rules get the declared-color suggestion; replacing the built-in
     by name keeps this from also flagging a dead rule *)
  check
    {|use standard
rule "play wild" priority 100:
  when card is wild and your turn
  do play the card, advance turn|};
  [%expect
    {|
    (warnings
     (((rule_name "quiet zeros") (kind Missing_set_color)
       (message
        "rule \"quiet zeros\" plays the card but never sets the color - the color to match stays what it was, not the played card's color")
       (fix ("set color from card")))))
    (warnings ())
    (warnings
     (((rule_name "play wild") (kind Missing_set_color)
       (message
        "rule \"play wild\" plays the card but never sets the color - add 'set color to declared' so the color the player picks takes effect")
       (fix ("set color to declared")))))
    |}]
;;

(* turn order exists only because rules demand it: a rule without the
   'your turn' guard fires for any player's action, even out of turn.
   Warn - omitting the guard is legitimate only for jump-in style rules. *)
let%expect_test "lint flags rules missing the your-turn guard" =
  (match
     Rule_parser.parse_ruleset_checked
       {|use standard
rule "free zeros" priority 60:
  when card is 0
  do play the card, set color from card, advance turn|}
   with
   | Error e -> print_s [%message (e : Error.t)]
   | Ok (_, warnings) -> print_s [%message (warnings : Rule_parser.Lint.t list)]);
  (* the guard must hold on EVERY path: or-ing it away doesn't count *)
  (match
     Rule_parser.parse_ruleset_checked
       {|use standard
rule "sneaky" priority 60:
  when your turn or player draws
  do advance turn|}
   with
   | Error e -> print_s [%message (e : Error.t)]
   | Ok (_, warnings) ->
     print_s
       [%message
         (List.map warnings ~f:(fun w -> w.Rule_parser.Lint.rule_name, w.kind)
          : (string * Rule_parser.Lint.Kind.t) list)]);
  [%expect
    {|
    (warnings
     (((rule_name "free zeros") (kind Missing_turn)
       (message
        "rule \"free zeros\" has no 'your turn' condition - it fires for ANY player's action, even out of turn (write 'not your turn' explicitly if jump-in is what you mean)")
       (fix ("your turn")))))
    ("List.map warnings ~f:(fun w -> (w.Rule_parser.Lint.rule_name, w.kind))"
     ((sneaky Missing_turn)))
    |}]
;;

(* a number condition wins the card click like any card condition, so the
   missing-play lint must fire for it too *)
let%expect_test "lint treats card is <number> as a card-play condition" =
  (match
     Rule_parser.parse_ruleset_checked
       {|use standard
rule "lucky sevens" priority 115:
  when card is 7 and your turn
  do set color to red|}
   with
   | Error e -> print_s [%message (e : Error.t)]
   | Ok (_, warnings) -> print_s [%message (warnings : Rule_parser.Lint.t list)]);
  [%expect
    {|
    (warnings
     (((rule_name "lucky sevens") (kind Missing_play)
       (message
        "rule \"lucky sevens\" fires when a card is played but has no 'play the card' effect - the card will stay in the hand")
       (fix ("play the card")))))
    |}]
;;

(* seven-zero: a 7 trades entire hands with the next seat (in play
   direction), a 0 sends every hand one seat along *)
let%expect_test "seven zero add-on swaps and rotates hands" =
  let rules =
    Rule_parser.parse_ruleset {|use standard
use seven zero|}
    |> Or_error.ok_exn
  in
  let hands (t : Game_state.t) = List.map t.players ~f:Player.get_hand in
  let seven = { Card.color = Red; value = Seven; id = 800 } in
  let zero = { Card.color = Red; value = Zero; id = 801 } in
  let a2 = { Card.color = Blue; value = Two; id = 802 } in
  let b1 = { Card.color = Green; value = Three; id = 803 } in
  let b2 = { Card.color = Green; value = Four; id = 804 } in
  let c1 = { Card.color = Yellow; value = Nine; id = 805 } in
  let top = { Card.color = Red; value = Five; id = 806 } in
  let state cards =
    Game_state.for_testing
      ~player_hands:[ "a", cards; "b", [ b1; b2 ]; "c", [ c1 ] ]
      ~top_card:top
      ~draw_pile:[]
      ~pending_draws:0
      ~turn:0
  in
  (* a 7 without a named target is rejected - the UI uses this to ask *)
  (match
     Rule_engine.apply_action rules (state [ seven; a2 ]) ~player_id:0
       ~action:(Play { card_id = 800; declared_color = None; swap_with = None })
   with
   | Ok _ -> print_endline "unexpectedly legal"
   | Error e -> print_s [%message (e : Error.t)]);
  (* the 7, aimed at c: a receives c's hand; c gets a's leftovers *)
  let t =
    Rule_engine.apply_action rules (state [ seven; a2 ]) ~player_id:0
      ~action:(Play { card_id = 800; declared_color = None; swap_with = Some "c" })
    |> Or_error.ok_exn
  in
  print_s [%message "after the 7" (hands t : int list list) (t.turn : int)];
  (* the 0: every hand moves one seat clockwise (a->b, b->c, c->a) *)
  let t =
    Rule_engine.apply_action rules (state [ zero; a2 ]) ~player_id:0
      ~action:(Play { card_id = 801; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  print_s [%message "after the 0" (hands t : int list list) (t.turn : int)];
  [%expect
    {|
    (e "Choose another player to aim this card at")
    ("after the 7" ("hands t" ((805) (804 803) (802))) (t.turn 1))
    ("after the 0" ("hands t" ((805) (802) (804 803))) (t.turn 1))
    |}]
;;

(* direction matters: after a reverse, the 0 rotates the other way *)
let%expect_test "rotate hands respects a reversed direction" =
  let rules =
    Rule_parser.parse_ruleset {|use standard
use seven zero|}
    |> Or_error.ok_exn
  in
  let rev = { Card.color = Red; value = Reverse; id = 810 } in
  let zero = { Card.color = Red; value = Zero; id = 811 } in
  let a2 = { Card.color = Blue; value = Two; id = 816 } in
  let b1 = { Card.color = Green; value = Three; id = 812 } in
  let c2 = { Card.color = Yellow; value = Two; id = 814 } in
  let top = { Card.color = Red; value = Five; id = 815 } in
  let hands (t : Game_state.t) = List.map t.players ~f:Player.get_hand in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", [ rev; a2 ]; "b", [ b1 ]; "c", [ zero; c2 ] ]
      ~top_card:top
      ~draw_pile:[]
      ~pending_draws:0
      ~turn:0
  in
  (* a reverses: direction flips and the turn goes a -> c *)
  let t =
    Rule_engine.apply_action rules t ~player_id:0
      ~action:(Play { card_id = 810; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  print_s [%message (t.direction : Direction.t) (t.turn : int)];
  (* c plays the red 0: counter-clockwise, so c's hand goes to b, b's to a,
     a's to c *)
  let t =
    Rule_engine.apply_action rules t ~player_id:2
      ~action:(Play { card_id = 811; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  print_s [%message "after the 0" (hands t : int list list) (t.turn : int)];
  [%expect
    {|
    ((t.direction Counter) (t.turn 2))
    ("after the 0" ("hands t" ((812) (814) (816))) (t.turn 1))
    |}]
;;

(* winner-before-swap: going out on your last 7 wins and no hands move *)
let%expect_test "going out on a 7 wins without swapping" =
  let rules =
    Rule_parser.parse_ruleset {|use standard
use seven zero|}
    |> Or_error.ok_exn
  in
  let seven = { Card.color = Red; value = Seven; id = 820 } in
  let b1 = { Card.color = Green; value = Three; id = 821 } in
  let top = { Card.color = Red; value = Five; id = 822 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", [ seven ]; "b", [ b1 ] ]
      ~top_card:top
      ~draw_pile:[]
      ~pending_draws:0
      ~turn:0
  in
  let t =
    Rule_engine.apply_action rules t ~player_id:0
      ~action:(Play { card_id = 820; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  print_s
    [%message
      (t.winner : int option)
        (List.map t.players ~f:Player.get_hand : int list list)];
  [%expect
    {| ((t.winner (0)) ("List.map t.players ~f:Player.get_hand" (() (821)))) |}]
;;

(* swapping yourself INTO a one-card hand opens your own UNO catch window,
   because the window is recomputed from the actor's final hand *)
let%expect_test "swapping into a one-card hand leaves you catchable" =
  let rules =
    Rule_parser.parse_ruleset {|use standard
use seven zero|}
    |> Or_error.ok_exn
  in
  let seven = { Card.color = Red; value = Seven; id = 830 } in
  let a2 = { Card.color = Blue; value = Two; id = 831 } in
  let b1 = { Card.color = Green; value = Three; id = 832 } in
  let top = { Card.color = Red; value = Five; id = 833 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", [ seven; a2 ]; "b", [ b1 ]; "c", [] ]
      ~top_card:top
      ~draw_pile:[]
      ~pending_draws:0
      ~turn:0
  in
  let t =
    Rule_engine.apply_action rules t ~player_id:0
      ~action:(Play { card_id = 830; declared_color = None; swap_with = Some "b" })
    |> Or_error.ok_exn
  in
  print_s
    [%message
      (t.uno_vulnerable : int option)
        (List.map t.players ~f:Player.get_hand : int list list)];
  [%expect
    {|
    ((t.uno_vulnerable (0))
     ("List.map t.players ~f:Player.get_hand" ((832) (831) ())))
    |}]
;;

(* the chaos effect: every player except the actor draws *)
let%expect_test "everyone else draws" =
  let rules =
    Rule_parser.parse_ruleset
      {|use standard
rule "party nines" priority 60:
  when card is 9 and (card matches color or card matches value) and your turn
  do play the card, set color from card, everyone else draws 2 cards, advance turn|}
    |> Or_error.ok_exn
  in
  let nine = { Card.color = Red; value = Nine; id = 840 } in
  let top = { Card.color = Red; value = Five; id = 841 } in
  let pile =
    List.init 4 ~f:(fun i -> { Card.color = Card.Color.Blue; value = Two; id = 850 + i })
  in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", [ nine ]; "b", []; "c", [] ]
      ~top_card:top
      ~draw_pile:pile
      ~pending_draws:0
      ~turn:0
  in
  let t =
    Rule_engine.apply_action rules t ~player_id:0
      ~action:(Play { card_id = 840; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  print_s
    [%message
      (List.map t.players ~f:(fun p -> List.length (Player.get_hand p)) : int list)
        (List.length t.draw_pile : int)
        (t.winner : int option)];
  [%expect
    {|
    (("List.map t.players ~f:(fun p -> List.length (Player.get_hand p))" (0 2 2))
     ("List.length t.draw_pile" 0) (t.winner (0)))
    |}]
;;

(* the pure diff behind the swap/rotate table animations: whole hands
   changing owners, never fooled by ordinary plays or draws *)
let%expect_test "hand_moves spots swaps and rotates, ignores normal moves" =
  let rules =
    Rule_parser.parse_ruleset {|use standard
use seven zero|}
    |> Or_error.ok_exn
  in
  let seven = { Card.color = Red; value = Seven; id = 860 } in
  let zero = { Card.color = Red; value = Zero; id = 866 } in
  let a2 = { Card.color = Blue; value = Two; id = 861 } in
  let b1 = { Card.color = Green; value = Three; id = 862 } in
  let c1 = { Card.color = Yellow; value = Nine; id = 863 } in
  let top = { Card.color = Red; value = Five; id = 864 } in
  let fresh = { Card.color = Blue; value = One; id = 865 } in
  let state cards =
    Game_state.for_testing
      ~player_hands:[ "a", cards; "b", [ b1 ]; "c", [ c1 ] ]
      ~top_card:top
      ~draw_pile:[ fresh ]
      ~pending_draws:0
      ~turn:0
  in
  let moves before ~after ~played =
    Game_state.hand_moves ~before ~after ~played
  in
  let before = state [ seven; a2 ] in
  let after =
    Rule_engine.apply_action rules before ~player_id:0
      ~action:(Play { card_id = 860; declared_color = None; swap_with = Some "b" })
    |> Or_error.ok_exn
  in
  print_s [%message "swap" (moves before ~after ~played:(Some 860) : (int * int) list)];
  let before = state [ zero; a2 ] in
  let after =
    Rule_engine.apply_action rules before ~player_id:0
      ~action:(Play { card_id = 866; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  print_s [%message "rotate" (moves before ~after ~played:(Some 866) : (int * int) list)];
  let before = state [ a2 ] in
  let after =
    Rule_engine.apply_action rules before ~player_id:0 ~action:Draw
    |> Or_error.ok_exn
  in
  print_s [%message "draw" (moves before ~after ~played:None : (int * int) list)];
  [%expect
    {|
    (swap ("moves before ~after ~played:(Some 860)" ((1 0) (0 1))))
    (rotate ("moves before ~after ~played:(Some 866)" ((2 0) (0 1) (1 2))))
    (draw ("moves before ~after ~played:None" ()))
    |}]
;;

(* the server marks which playable cards still need a swap target by
   simulating each play - that is what drives the UI's player picker *)
let%expect_test "playable_and_swap_ids flags chosen-swap cards" =
  let rules =
    Rule_parser.parse_ruleset {|use standard
use seven zero|}
    |> Or_error.ok_exn
  in
  let seven = { Card.color = Red; value = Seven; id = 870 } in
  let matching = { Card.color = Red; value = Two; id = 871 } in
  let dud = { Card.color = Blue; value = Three; id = 872 } in
  let top = { Card.color = Red; value = Five; id = 873 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", [ seven; matching; dud ]; "b", [] ]
      ~top_card:top
      ~draw_pile:[]
      ~pending_draws:0
      ~turn:0
  in
  let playable, needs_target =
    Rule_engine.playable_and_swap_ids rules t ~player_id:0
  in
  print_s [%message (playable : int list) (needs_target : int list)];
  [%expect {| ((playable (871 870)) (needs_target (870))) |}]
;;

(* the DSL's first setting (deal N cards) and its first blocking effect
   (reject "...") - together they cover "more than 7 cards" and "no going
   out on an action card" style table rules *)
let%expect_test "deal directive and reject effect parse; bad deals rejected" =
  (match
     Rule_parser.parse_ruleset_full
       {|use standard
deal 9 cards
rule "no action finish" priority 200:
  when card is action and hand size = 1
  do reject "you cannot go out on an action card"|}
   with
   | Error e -> print_s [%message (e : Error.t)]
   | Ok { rules; hand_size } ->
     print_s [%message (List.length rules : int) (hand_size : int option)]);
  (* a later deal line wins; absent means None (server default) *)
  (match
     Rule_parser.parse_ruleset_full {|deal 5 cards
deal 12 cards
rule "x": when always do advance turn|}
   with
   | Error e -> print_s [%message (e : Error.t)]
   | Ok { rules = _; hand_size } -> print_s [%message (hand_size : int option)]);
  (match
     Rule_parser.parse_ruleset_full {|rule "x": when always do advance turn|}
   with
   | Error e -> print_s [%message (e : Error.t)]
   | Ok { rules = _; hand_size } -> print_s [%message (hand_size : int option)]);
  (match
     Rule_parser.parse_ruleset_full {|deal 99 cards
rule "x": when always do advance turn|}
   with
   | Ok _ -> print_endline "unexpectedly parsed"
   | Error e -> print_s [%message (e : Error.t)]);
  [%expect
    {|
    (("List.length rules" 12) (hand_size (9)))
    (hand_size (12))
    (hand_size ())
    (e "line 1: 'deal 99 cards' - deal between 1 and 30")
    |}]
;;

(* reject makes the move ILLEGAL: the rejection carries the author's
   message, the card doesn't count as playable, and the same card is fine
   again once it isn't the last one *)
let%expect_test "reject blocks going out on an action card" =
  let rules =
    Rule_parser.parse_ruleset
      {|use standard
rule "no action finish" priority 200:
  when card is action and hand size = 1
  do reject "you cannot go out on an action card"|}
    |> Or_error.ok_exn
  in
  let skip = { Card.color = Red; value = Skip; id = 880 } in
  let spare = { Card.color = Blue; value = Two; id = 881 } in
  let b1 = { Card.color = Green; value = Three; id = 882 } in
  let top = { Card.color = Red; value = Five; id = 883 } in
  let state cards =
    Game_state.for_testing
      ~player_hands:[ "a", cards; "b", [ b1 ]; "c", [] ]
      ~top_card:top
      ~draw_pile:[]
      ~pending_draws:0
      ~turn:0
  in
  (* last card: blocked, and not even marked playable *)
  let t = state [ skip ] in
  (match
     Rule_engine.apply_action rules t ~player_id:0
       ~action:(Play { card_id = 880; declared_color = None; swap_with = None })
   with
   | Ok _ -> print_endline "unexpectedly legal"
   | Error e -> print_s [%message (e : Error.t)]);
  print_s
    [%message
      (Rule_engine.playable_card_ids rules t ~player_id:0 : int list)];
  (* with another card in hand the same skip plays normally *)
  let t =
    Rule_engine.apply_action rules (state [ skip; spare ]) ~player_id:0
      ~action:(Play { card_id = 880; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  print_s [%message "skip played" (t.turn : int)];
  [%expect
    {|
    (e "you cannot go out on an action card")
    ("Rule_engine.playable_card_ids rules t ~player_id:0" ())
    ("skip played" (t.turn 2))
    |}]
;;

(* reject-rules are exempt from the missing-play and missing-turn nags:
   not playing is the point, and table constraints apply to jump-ins too *)
let%expect_test "lint leaves blocking rules alone" =
  (match
     Rule_parser.parse_ruleset_checked
       {|use standard
rule "no action finish" priority 200:
  when card is action and hand size = 1
  do reject "no action finish"|}
   with
   | Error e -> print_s [%message (e : Error.t)]
   | Ok (_, warnings) -> print_s [%message (warnings : Rule_parser.Lint.t list)]);
  [%expect {| (warnings ()) |}]
;;

(* the second setting: turn timer N seconds (or off), same replace-and-reset
   semantics as deal *)
let%expect_test "turn timer directive parses with bounds" =
  let check text =
    match Rule_parser.parse_ruleset_full text with
    | Error e -> print_s [%message (e : Error.t)]
    | Ok { turn_timer; _ } -> print_s [%message (turn_timer : int option)]
  in
  check {|turn timer 15 seconds
rule "x": when always do advance turn|};
  check {|turn timer off
rule "x": when always do advance turn|};
  check {|rule "x": when always do advance turn|};
  check {|turn timer 3 seconds
rule "x": when always do advance turn|};
  [%expect
    {|
    (turn_timer (15))
    (turn_timer (0))
    (turn_timer ())
    (e "line 1: 'turn timer 3 seconds' - between 5 and 300, or off")
    |}]
;;

(* the targeted attack: the actor aims the draw at any player, and - unlike
   swaps - a winning final card still delivers, matching official +2/+4 *)
let%expect_test "chosen player draws hits the aimed player" =
  let rules =
    Rule_parser.parse_ruleset
      {|use standard
rule "play plus four" priority 110:
  when card is plus four and your turn
  do play the card, set color to declared, chosen player draws 4 cards, advance turn|}
    |> Or_error.ok_exn
  in
  let plus4 = { Card.color = NoColor; value = Wild4; id = 890 } in
  let a2 = { Card.color = Blue; value = Two; id = 891 } in
  let top = { Card.color = Red; value = Five; id = 892 } in
  let pile =
    List.init 4 ~f:(fun i ->
      { Card.color = Card.Color.Green; value = Card.Value.One; id = 893 + i })
  in
  let state cards =
    Game_state.for_testing
      ~player_hands:[ "a", cards; "b", []; "c", [] ]
      ~top_card:top
      ~draw_pile:pile
      ~pending_draws:0
      ~turn:0
  in
  (* no target: rejected with the picker marker *)
  (match
     Rule_engine.apply_action rules (state [ plus4; a2 ]) ~player_id:0
       ~action:
         (Play { card_id = 890; declared_color = Some Blue; swap_with = None })
   with
   | Ok _ -> print_endline "unexpectedly legal"
   | Error e -> print_s [%message (e : Error.t)]);
  (* aimed past the next player at c *)
  let t =
    Rule_engine.apply_action rules (state [ plus4; a2 ]) ~player_id:0
      ~action:
        (Play { card_id = 890; declared_color = Some Blue; swap_with = Some "c" })
    |> Or_error.ok_exn
  in
  print_s
    [%message
      "aimed at c"
        (List.map t.players ~f:(fun p -> List.length (Player.get_hand p)) : int list)
        (t.turn : int)];
  (* the winning +4 still delivers its cards *)
  let t =
    Rule_engine.apply_action rules (state [ plus4 ]) ~player_id:0
      ~action:
        (Play { card_id = 890; declared_color = Some Blue; swap_with = Some "c" })
    |> Or_error.ok_exn
  in
  print_s
    [%message
      "won with it"
        (t.winner : int option)
        (List.map t.players ~f:(fun p -> List.length (Player.get_hand p)) : int list)];
  [%expect
    {|
    (e "Choose another player to aim this card at")
    ("aimed at c"
     ("List.map t.players ~f:(fun p -> List.length (Player.get_hand p))" (1 0 4))
     (t.turn 1))
    ("won with it" (t.winner (0))
     ("List.map t.players ~f:(fun p -> List.length (Player.get_hand p))" (0 0 4)))
    |}]
;;

(* table-state conditions read the pile, direction and draw pile - usable
   on any action, not just card plays *)
let%expect_test "table-state conditions parse and fire" =
  (match
     Rule_parser.parse_ruleset
       {|rule "t": when top card is 7 and direction is counter and draw pile < 5 and top card is action and your turn do advance turn|}
   with
   | Ok [ rule ] -> print_s [%message (rule.Rule.condition : Rule.Condition.t)]
   | Ok _ -> print_endline "unexpected rule count"
   | Error e -> print_s [%message (e : Error.t)]);
  (* a draw tax that only exists while the pile is low *)
  let rules =
    Rule_parser.parse_ruleset
      {|use standard
rule "low pile tax" priority 60:
  when player draws and draw pile < 3 and your turn
  do draw 2 cards, advance turn|}
    |> Or_error.ok_exn
  in
  let top = { Card.color = Red; value = Five; id = 897 } in
  let pile =
    [ { Card.color = Card.Color.Green; value = Card.Value.One; id = 898 }
    ; { Card.color = Card.Color.Green; value = Card.Value.Two; id = 899 }
    ]
  in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", []; "b", [] ]
      ~top_card:top
      ~draw_pile:pile
      ~pending_draws:0
      ~turn:0
  in
  let t =
    Rule_engine.apply_action rules t ~player_id:0 ~action:Draw
    |> Or_error.ok_exn
  in
  print_s
    [%message
      "taxed draw"
        (List.length (Player.get_hand (List.nth_exn t.players 0)) : int)
        (t.turn : int)];
  [%expect
    {|
    (rule.Rule.condition
     (And (TopCardIsNumber 7)
      (And (Not DirectionIsClockwise)
       (And (DrawPileLessThan 5) (And TopCardIsAction IsPlayerTurn)))))
    ("taxed draw" ("List.length (Player.get_hand (List.nth_exn t.players 0))" 2)
     (t.turn 1))
    |}]
;;

let%expect_test "opponent-hand conditions parse and fire" =
  (match
     Rule_parser.parse_ruleset
       {|rule "t": when any opponent has 1 card and any opponent has more than 10 cards do advance turn|}
   with
   | Ok [ rule ] -> print_s [%message (rule.Rule.condition : Rule.Condition.t)]
   | Ok _ -> print_endline "unexpected rule count"
   | Error e -> print_s [%message (e : Error.t)]);
  (* a defensive draw that only exists while somebody is on their last card *)
  let rules =
    Rule_parser.parse_ruleset
      {|use standard
rule "panic draw" priority 60:
  when player draws and any opponent has 1 card and your turn
  do draw 2 cards, advance turn|}
    |> Or_error.ok_exn
  in
  let top = { Card.color = Red; value = Five; id = 900 } in
  let pile =
    List.init 6 ~f:(fun i ->
      { Card.color = Card.Color.Green; value = Card.Value.One; id = 901 + i })
  in
  let last_card = { Card.color = Card.Color.Blue; value = Card.Value.Two; id = 950 } in
  let fire =
    Game_state.for_testing
      ~player_hands:[ "a", []; "b", [ last_card ] ]
      ~top_card:top
      ~draw_pile:pile
      ~pending_draws:0
      ~turn:0
  in
  let fire =
    Rule_engine.apply_action rules fire ~player_id:0 ~action:Draw
    |> Or_error.ok_exn
  in
  print_s
    [%message
      "opponent at 1 card: panic draw fires"
        (List.length (Player.get_hand (List.nth_exn fire.players 0)) : int)
        (fire.turn : int)];
  (* same table, but b holds two cards - the rule stays out of the way *)
  let calm =
    Game_state.for_testing
      ~player_hands:
        [ "a", []
        ; ( "b"
          , [ last_card
            ; { Card.color = Card.Color.Blue; value = Card.Value.Three; id = 951 }
            ] )
        ]
      ~top_card:top
      ~draw_pile:pile
      ~pending_draws:0
      ~turn:0
  in
  let calm =
    Rule_engine.apply_action rules calm ~player_id:0 ~action:Draw
    |> Or_error.ok_exn
  in
  print_s
    [%message
      "opponent safe: normal draw"
        (List.length (Player.get_hand (List.nth_exn calm.players 0)) : int)
        (calm.turn : int)];
  [%expect {|
    (rule.Rule.condition
     (And (AnyOpponentHandEquals 1) (AnyOpponentHandGreaterThan 10)))
    ("opponent at 1 card: panic draw fires"
     ("List.length (Player.get_hand (List.nth_exn fire.players 0))" 2)
     (fire.turn 1))
    ("opponent safe: normal draw"
     ("List.length (Player.get_hand (List.nth_exn calm.players 0))" 1)
     (calm.turn 1))
    |}]
;;

let%expect_test "remove rule drops a preset rule; positional; caseless" =
  let count text =
    match Rule_parser.parse_ruleset text with
    | Ok rules -> printf "%d rules\n" (List.length rules)
    | Error e -> print_s [%message (e : Error.t)]
  in
  count {|use standard|};
  count {|use standard
remove rule "play plus four"|};
  (* caseless, like redefinition *)
  count {|use standard
remove rule "Play Plus Four"|};
  (* remove then redefine: the later definition re-adds the name *)
  count
    {|use standard
remove rule "play plus four"
rule "play plus four" priority 110:
  when card is plus four and your turn
  do play the card, set color to declared, chosen player draws 4 cards, advance turn|};
  (* nothing defined above the removal yet *)
  count {|remove rule "play plus four"
use standard|};
  (* unknown name lists what exists *)
  count {|use seven zero
remove rule "play plus four"|};
  (* the quoted name is required *)
  count {|use standard
remove rule play plus four|};
  [%expect {|
    11 rules
    10 rules
    10 rules
    11 rules
    (e
     "line 1: no rule named \"play plus four\" to remove (defined so far: none - put it after the `use` line)")
    (e
     "line 2: no rule named \"play plus four\" to remove (defined so far: sevens swap hands, zeros rotate hands)")
    (e
     "line 2: remove rule needs the quoted rule name, like: remove rule \"play plus four\"")
    |}]
;;

(* ---------- regressions for the review fixes ---------- *)

(* the self-claim rule stands aside while someone else's window is open,
   so being down to one card yourself no longer swallows your catch *)
let%expect_test "a one-card holder can still catch someone else's UNO" =
  let playable = { Card.color = Red; value = Seven; id = 950 } in
  let spare = { Card.color = Blue; value = Two; id = 951 } in
  let top = { Card.color = Red; value = Three; id = 952 } in
  let filler n = { Card.color = Green; value = Four; id = 953 + n } in
  let t =
    Game_state.for_testing
      ~player_hands:
        [ "a", [ playable; spare ]
        ; "b", [ filler 0 ] (* the catcher is on uno themselves *)
        ; "c", [ filler 1; filler 2 ]
        ]
      ~top_card:top
      ~draw_pile:(Game_state.create_card_deck ())
      ~pending_draws:0
      ~turn:0
  in
  let t =
    Rule_engine.apply_action
      rules
      t
      ~player_id:0
      ~action:(Play { card_id = 950; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  let t =
    Rule_engine.apply_action rules t ~player_id:1 ~action:Call_uno
    |> Or_error.ok_exn
  in
  let victim = hand_of t 0 in
  let catcher = hand_of t 1 in
  print_s
    [%message (victim : int) (catcher : int) (t.uno_vulnerable : int option)];
  [%expect {| ((victim 3) (catcher 1) (t.uno_vulnerable ())) |}]
;;

(* both piles empty: a draw click yields nothing and passes the turn
   instead of erroring the seat into an unplayable state *)
let%expect_test "a draw click on a dry deck passes the turn" =
  let top = { Card.color = Red; value = Five; id = 970 } in
  let blue = { Card.color = Blue; value = Two; id = 971 } in
  let green = { Card.color = Green; value = Four; id = 972 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", [ blue ]; "b", [ green ] ]
      ~top_card:top
      ~draw_pile:[]
      ~pending_draws:0
      ~turn:0
  in
  let t =
    Rule_engine.apply_action rules t ~player_id:0 ~action:Draw
    |> Or_error.ok_exn
  in
  print_s
    [%message (hand_of t 0 : int) (t.turn : int) (t.drew_playable : bool)];
  [%expect {| (("hand_of t 0" 1) (t.turn 1) (t.drew_playable false)) |}]
;;

(* a +2 near the end of the deck delivers what is left (here: only the
   recycled old top card) instead of rejecting the whole play *)
let%expect_test "a +2 short-draws when the piles nearly run out" =
  let top = { Card.color = Red; value = Five; id = 975 } in
  let plus = { Card.color = Red; value = Plus; id = 976 } in
  let blue = { Card.color = Blue; value = Two; id = 977 } in
  let green = { Card.color = Green; value = Four; id = 978 } in
  let green2 = { Card.color = Green; value = Four; id = 979 } in
  let t =
    Game_state.for_testing
      ~player_hands:
        [ "a", [ plus; blue ]; "b", [ green ]; "c", [ green2 ] ]
      ~top_card:top
      ~draw_pile:[]
      ~pending_draws:0
      ~turn:0
  in
  let t =
    Rule_engine.apply_action
      rules
      t
      ~player_id:0
      ~action:(Play { card_id = 976; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  print_s
    [%message (hand_of t 0 : int) (hand_of t 1 : int) (t.turn : int)];
  [%expect
    {| (("hand_of t 0" 1) ("hand_of t 1" 2) (t.turn 2)) |}]
;;

(* availability is simulated, so a blocking rule that outranks the
   permissive pass rule hides the pass button instead of offering a pass
   that can never land *)
let%expect_test "pass_available honors a winning reject-on-pass rule" =
  let rules =
    Rule_parser.parse_ruleset
      (Presets.stacking_text
       ^ {|
rule "no bailing out" priority 300:
  when player passes and stack is open
  do reject "finish your stack"
|})
    |> Or_error.ok_exn
  in
  let top = { Card.color = Red; value = Three; id = 980 } in
  let five = { Card.color = Red; value = Five; id = 981 } in
  let spare = { Card.color = Blue; value = Two; id = 982 } in
  let green = { Card.color = Green; value = Four; id = 983 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", [ five; spare ]; "b", [ green ] ]
      ~top_card:top
      ~draw_pile:[]
      ~pending_draws:0
      ~turn:0
  in
  let t =
    Rule_engine.apply_action
      rules
      t
      ~player_id:0
      ~action:(Play { card_id = 981; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  print_s
    [%message
      (t.stacking_value : Card.Value.t option)
        (Rule_engine.pass_available rules t : bool)];
  (match Rule_engine.apply_action rules t ~player_id:0 ~action:Pass with
   | Ok _ -> print_endline "pass unexpectedly accepted"
   | Error e -> print_s [%message (e : Error.t)]);
  [%expect
    {|
    ((t.stacking_value (Five)) ("Rule_engine.pass_available rules t" false))
    (e "finish your stack")
    |}]
;;

(* the seven-zero rules are blocked mid-stack: a 7 played into an open
   stack no longer swaps hands and walks away, stranding the stack *)
let%expect_test "a mid-stack 7 is illegal under stacking + seven zero" =
  let rules =
    Rule_parser.parse_ruleset {|use stacking
use seven zero|} |> Or_error.ok_exn
  in
  let top = { Card.color = Red; value = Three; id = 985 } in
  let five = { Card.color = Red; value = Five; id = 986 } in
  let seven = { Card.color = Red; value = Seven; id = 987 } in
  let spare = { Card.color = Blue; value = Two; id = 988 } in
  let green = { Card.color = Green; value = Four; id = 989 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", [ five; seven; spare ]; "b", [ green ] ]
      ~top_card:top
      ~draw_pile:[]
      ~pending_draws:0
      ~turn:0
  in
  let t =
    Rule_engine.apply_action
      rules
      t
      ~player_id:0
      ~action:(Play { card_id = 986; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  (match
     Rule_engine.apply_action
       rules
       t
       ~player_id:0
       ~action:
         (Play { card_id = 987; declared_color = None; swap_with = Some "b" })
   with
   | Ok _ -> print_endline "seven unexpectedly accepted mid-stack"
   | Error e -> print_s [%message (e : Error.t)]);
  (* closing the stack normally still works *)
  let t =
    Rule_engine.apply_action rules t ~player_id:0 ~action:Pass
    |> Or_error.ok_exn
  in
  print_s [%message (t.stacking_value : Card.Value.t option) (t.turn : int)];
  [%expect
    {|
    (e "Illegal move: no rule allows that right now")
    ((t.stacking_value ()) (t.turn 1))
    |}]
;;

(* jump-in is number-cards-only: a jumped +2 twin used to play as a blank
   and leave the pending penalty to whoever held the turn after the jump *)
let%expect_test "jump-in rejects action cards" =
  let rules = Rule_engine.Ruleset.stacking_jump_in_variant in
  let top = { Card.color = Red; value = Three; id = 990 } in
  let plus_a = { Card.color = Red; value = Plus; id = 991 } in
  let spare = { Card.color = Blue; value = Two; id = 992 } in
  let green = { Card.color = Green; value = Four; id = 993 } in
  let plus_c = { Card.color = Red; value = Plus; id = 994 } in
  let green2 = { Card.color = Green; value = Four; id = 995 } in
  let d1 = { Card.color = Yellow; value = One; id = 996 } in
  let d2 = { Card.color = Yellow; value = Two; id = 997 } in
  let t =
    Game_state.for_testing
      ~player_hands:
        [ "a", [ plus_a; spare ]; "b", [ green ]; "c", [ plus_c; green2 ] ]
      ~top_card:top
      ~draw_pile:[ d1; d2 ]
      ~pending_draws:0
      ~turn:0
  in
  let t =
    Rule_engine.apply_action
      rules
      t
      ~player_id:0
      ~action:(Play { card_id = 991; declared_color = None; swap_with = None })
    |> Or_error.ok_exn
  in
  (* c holds the exact twin of the top card - but it is an action card *)
  (match
     Rule_engine.apply_action
       rules
       t
       ~player_id:2
       ~action:
         (Play { card_id = 994; declared_color = None; swap_with = None })
   with
   | Ok _ -> print_endline "action-card jump unexpectedly accepted"
   | Error e -> print_s [%message (e : Error.t)]);
  (* so the penalty still lands on its intended victim *)
  let t =
    Rule_engine.apply_action rules t ~player_id:1 ~action:Draw
    |> Or_error.ok_exn
  in
  print_s
    [%message (hand_of t 1 : int) (t.pending_draws : int) (t.turn : int)];
  [%expect
    {|
    (e "Illegal move: no rule allows that right now")
    (("hand_of t 1" 3) (t.pending_draws 0) (t.turn 2))
    |}]
;;

(* the drawn card is judged by the ruleset in force, not official-rules
   matching, so the play-or-pass window agrees with the hand highlights *)
let%expect_test "draw-and-decide judges the drawn card by the live ruleset" =
  let rules =
    Rule_parser.parse_ruleset
      (Presets.standard_text
       ^ {|
rule "blue anywhere" priority 60:
  when card is blue and your turn
  do play the card, set color from card, advance turn
|})
    |> Or_error.ok_exn
  in
  let top = { Card.color = Red; value = Five; id = 1000 } in
  let unplayable = { Card.color = Green; value = Four; id = 1001 } in
  let blue = { Card.color = Blue; value = Nine; id = 1002 } in
  let filler = { Card.color = Yellow; value = One; id = 1003 } in
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", [ unplayable ]; "b", [ filler ] ]
      ~top_card:top
      ~draw_pile:[ blue ]
      ~pending_draws:0
      ~turn:0
  in
  let t =
    Rule_engine.apply_action rules t ~player_id:0 ~action:Draw
    |> Or_error.ok_exn
  in
  (* official rules call a blue 9 on a red 5 unplayable; the live ruleset
     does not, so the turn must stay open *)
  print_s [%message (t.drew_playable : bool) (t.turn : int)];
  [%expect {| ((t.drew_playable true) (t.turn 0)) |}]
;;

let%expect_test "a huge number is a parse error, not an exception" =
  (match
     Rule_parser.parse_ruleset
       {|rule "big" priority 99999999999999999999: when your turn do advance turn|}
   with
   | Ok _ -> print_endline "unexpectedly parsed"
   | Error e -> print_s [%message (e : Error.t)]);
  [%expect {| (e "line 1: number '99999999999999999999' is too large") |}]
;;
