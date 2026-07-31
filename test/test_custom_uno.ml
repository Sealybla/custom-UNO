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
  let hand_sizes = List.map t.players ~f:(fun p -> List.length (Player.get_hand p)) in
  print_s
    [%message
      (hand_sizes : int list)
        (List.length t.draw_pile : int)
        (t.turn : int)
        (t.winner : int option)];
  [%expect {|
    ((hand_sizes (7 7 7)) ("List.length t.draw_pile" 86) (t.turn 0)
     (t.winner ()))
    |}]
;;

(* let%expect_test "wrong player's turn is rejected" =
  let t = make_state () in
  let result = Game_state.apply_action t ~player_id:1 ~action:Draw in
  print_s [%message (Or_error.is_error result : bool)];
  [%expect {| ("Or_error.is_error result" true) |}]
;;

let%expect_test "rejected action leaves state unchanged" =
  let t = make_state () in
  (match Game_state.apply_action t ~player_id:1 ~action:Draw with
   | Ok _ -> print_endline "unexpectedly succeeded"
   | Error _ -> ());
  (* t is immutable, so this is trivially true — but it documents the property *)
  let t2 = make_state () in
  print_s [%message (Game_state.equal t t2 : bool)];
  [%expect {| ("Game_state.equal t t2" true) |}]
;;

let%expect_test "draw advances turn and grows hand" =
  let t = make_state () in
  let t' = Game_state.apply_action t ~player_id:0 ~action:Draw |> Or_error.ok_exn in
  let before = List.length (Player.get_hand (List.nth_exn t.players 0)) in
  let after = List.length (Player.get_hand (List.nth_exn t'.players 0)) in
  print_s [%message (before : int) (after : int) (t'.turn : int)];
  [%expect {| ((before 7) (after 8) (t'.turn 1)) |}]
;; *)

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
    Rule_engine.apply_action Rule_engine.Ruleset.default t ~player_id:0 ~action:Draw
    |> Or_error.ok_exn
  in
  let after = List.length (Player.get_hand (List.nth_exn t'.players 0)) in
  print_s
    [%message (after : int) (t'.turn : int) (t'.drew_playable : bool)];
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
    Rule_engine.apply_action Rule_engine.Ruleset.default t ~player_id:0 ~action:Draw
    |> Or_error.ok_exn
  in
  print_s
    [%message
      "after draw" (t.turn : int) (t.drew_playable : bool)
        (Rule_engine.pass_available Rule_engine.Ruleset.default t : bool)];
  (* drawing again while deciding is not allowed *)
  let redraw =
    Rule_engine.apply_action Rule_engine.Ruleset.default t ~player_id:0 ~action:Draw
  in
  print_s [%message (Or_error.is_error redraw : bool)];
  let t =
    Rule_engine.apply_action Rule_engine.Ruleset.default t ~player_id:0 ~action:Pass
    |> Or_error.ok_exn
  in
  print_s [%message "after pass" (t.turn : int) (t.drew_playable : bool)];
  [%expect {|
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
    Rule_engine.apply_action Rule_engine.Ruleset.default t ~player_id:0 ~action:Pass
  in
  print_s
    [%message
      (Or_error.is_error result : bool)
        (Rule_engine.pass_available Rule_engine.Ruleset.default t : bool)];
  [%expect {|
    (("Or_error.is_error result" true)
     ("Rule_engine.pass_available Rule_engine.Ruleset.default t" false))
    |}]
;;

let%expect_test "full game plays to completion" =
  let resolve_hand state player =
    List.filter_map (Player.get_hand player) ~f:(fun id ->
      Game_state.Card_registry.find state.Game_state.card_registry id |> Or_error.ok)
  in
  let rec play state moves =
    if moves > 1000
    then(
    print_endline "no winner after 1000 moves";
    let sizes = List.map state.Game_state.players ~f:(fun p -> List.length (Player.get_hand p)) in
      print_s [%message (sizes : int list) (state.Game_state.turn : int)
        (List.length state.Game_state.draw_pile : int)]) 
    else (
      match state.Game_state.winner with
      | Some id -> print_s [%message "winner" (id : int) (moves : int)]
      | None ->
        let player = List.nth_exn state.Game_state.players state.Game_state.turn in
        let hand = resolve_hand state player in
        let action =
          match
            Game_rules.choose_card ~hand ~top_card:state.Game_state.top_card
              ~current_color:state.Game_state.current_color
          with
          | Some card ->
            let declared_color =
              match card.Card.value with
              | Wild | Wild4 ->
                Some 
                (List.find_map hand ~f:(fun c ->
                  match c.Card.color with NoColor -> None | col -> Some col)
                |> Option.value ~default:Card.Color.Red)
              | _ -> None
            in
            Action.Client_to_server.Play { card_id = Card.get_id card; declared_color }
          | None -> Draw
        in
        (match
           Rule_engine.apply_action Rule_engine.Ruleset.default state
             ~player_id:state.Game_state.turn ~action
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
    Rule_engine.apply_action Rule_engine.Ruleset.stacking_variant t
      ~player_id:1 ~action:(Play { card_id = 201; declared_color = None })
    |> Or_error.ok_exn
  in
  print_s [%message "after stack" (t.pending_draws : int) (t.turn : int)];
  (* player 2 can't stack — draws the pending 4, pending resets to 0 *)
  let before = List.length (Player.get_hand (List.nth_exn t.players 2)) in
  let t =
    Rule_engine.apply_action Rule_engine.Ruleset.stacking_variant t
      ~player_id:2 ~action:Draw
    |> Or_error.ok_exn
  in
  let after = List.length (Player.get_hand (List.nth_exn t.players 2)) in
  print_s [%message "after penalty draw"
    (before : int) (after : int) (t.pending_draws : int) (t.turn : int)];
  [%expect {|
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
    Rule_engine.apply_action Rule_engine.Ruleset.stacking_variant t
      ~player_id:1 ~action:(Play { card_id = 300; declared_color = Some Red })
    |> Or_error.ok_exn
  in
  print_s [%message "after plus4 stack" (t.pending_draws : int) (t.turn : int)];
  (* player 2 can't continue — draws all 6, pending resets *)
  let before = List.length (Player.get_hand (List.nth_exn t.players 2)) in
  let t =
    Rule_engine.apply_action Rule_engine.Ruleset.stacking_variant t
      ~player_id:2 ~action:Draw
    |> Or_error.ok_exn
  in
  let after = List.length (Player.get_hand (List.nth_exn t.players 2)) in
  print_s [%message "after penalty draw"
    (before : int) (after : int) (t.pending_draws : int) (t.turn : int)];
  [%expect {|
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
      ~action:(Play { card_id = 402; declared_color = None })
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
      ~action:(Play { card_id = 701; declared_color = None })
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
    Rule_engine.apply_action Rule_engine.Ruleset.stacking_variant t
      ~player_id:0 ~action:(Play { card_id = 500; declared_color = None })
    |> Or_error.ok_exn
  in
  print_s [%message "after first 7" (t.turn : int)
    (t.stacking_value : Card.Value.t option)
    (List.length (Player.get_hand (List.nth_exn t.players 0)) : int)];
  (* play second 7 — continues stack, turn still 0 *)
  let t =
    Rule_engine.apply_action Rule_engine.Ruleset.stacking_variant t
      ~player_id:0 ~action:(Play { card_id = 501; declared_color = None })
    |> Or_error.ok_exn
  in
  print_s [%message "after second 7" (t.turn : int)
    (List.length (Player.get_hand (List.nth_exn t.players 0)) : int)];
  (* pass — ends turn, clears stack *)
  let t =
    Rule_engine.apply_action Rule_engine.Ruleset.stacking_variant t
      ~player_id:0 ~action:Pass
    |> Or_error.ok_exn
  in
  print_s [%message "after pass" (t.turn : int)
    (t.stacking_value : Card.Value.t option)];
  [%expect {|
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
    Rule_engine.apply_action Rule_engine.Ruleset.stacking_variant t
      ~player_id:0 ~action:(Play { card_id = 650; declared_color = None })
    |> Or_error.ok_exn
  in
  let rejected action =
    Rule_engine.apply_action Rule_engine.Ruleset.stacking_variant t
      ~player_id:0 ~action
    |> Or_error.is_error
  in
  (* same color but different value, a special, and a draw are all illegal *)
  let red_three_rejected =
    rejected (Play { card_id = 652; declared_color = None })
  in
  let red_skip_rejected =
    rejected (Play { card_id = 653; declared_color = None })
  in
  let wild_rejected =
    rejected (Play { card_id = 654; declared_color = Some Red })
  in
  let draw_rejected = rejected Draw in
  (* the blue 7 continues the stack *)
  let t =
    Rule_engine.apply_action Rule_engine.Ruleset.stacking_variant t
      ~player_id:0 ~action:(Play { card_id = 651; declared_color = None })
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
  [%expect {|
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
    Rule_engine.apply_action Rule_engine.Ruleset.stacking_variant t
      ~player_id:0 ~action:(Play { card_id = 600; declared_color = None })
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
      { player = List.nth_exn t.players 0; card = w; declared_color = Some Red }
  in
  print_s
    [%message (Rule_engine.eval_condition t evt MatchesTopColor : bool)];
  let result =
    Rule_engine.apply_action Rule_engine.Ruleset.default t
      ~player_id:0 ~action:(Play { card_id = 610; declared_color = Some Red })
  in
  print_s [%message (Or_error.is_ok result : bool)];
  [%expect {|
    ("Rule_engine.eval_condition t evt MatchesTopColor" false)
    ("Or_error.is_ok result" true)
    |}]
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
    Rule_engine.apply_action Rule_engine.Ruleset.default t
      ~player_id:0 ~action:(Play { card_id = id; declared_color = None })
    |> Or_error.is_error
  in
  let blue_plus_on_red_five_rejected = try_play 800 in
  let green_skip_on_red_five_rejected = try_play 801 in
  print_s
    [%message
      (blue_plus_on_red_five_rejected : bool)
        (green_skip_on_red_five_rejected : bool)];
  [%expect {|
    ((blue_plus_on_red_five_rejected true)
     (green_skip_on_red_five_rejected true))
    |}]
;;

(* official 2-player rule: reverse acts like a skip, so the player who
   played it goes again; with 3+ players it only flips the direction *)
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
    Rule_engine.apply_action Rule_engine.Ruleset.default two_player
      ~player_id:0 ~action:(Play { card_id = 830; declared_color = None })
    |> Or_error.ok_exn
  in
  print_s
    [%message "two players" (t.turn : int) (t.direction : Direction.t)];
  let three_player =
    Game_state.for_testing
      ~player_hands:[ "a", [ rev; f ]; "b", []; "c", [] ]
      ~top_card:top
      ~draw_pile:[]
      ~pending_draws:0
      ~turn:0
  in
  let t =
    Rule_engine.apply_action Rule_engine.Ruleset.default three_player
      ~player_id:0 ~action:(Play { card_id = 830; declared_color = None })
    |> Or_error.ok_exn
  in
  print_s
    [%message "three players" (t.turn : int) (t.direction : Direction.t)];
  [%expect {|
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
    Rule_engine.apply_action Rule_engine.Ruleset.default t
      ~player_id:0 ~action:(Play { card_id = 810; declared_color = None })
    |> Or_error.ok_exn
  in
  (* immediate semantics: the victim draws 2 on the spot and is skipped *)
  let victim_hand = List.length (Player.get_hand (List.nth_exn t.players 1)) in
  print_s [%message (t.pending_draws : int) (t.turn : int) (victim_hand : int)];
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
    Rule_engine.apply_action Rule_engine.Ruleset.stacking_variant t
      ~player_id:0 ~action:(Play { card_id = 820; declared_color = Some Red })
    |> Or_error.ok_exn
  in
  let hand = List.length (Player.get_hand (List.nth_exn t.players 0)) in
  let top_unchanged = Card.equal t.top_card top in
  (* wild not played: hand went 2 -> 4 (penalty), turn passed, pending cleared *)
  print_s
    [%message
      (hand : int) (t.pending_draws : int) (t.turn : int) (top_unchanged : bool)];
  [%expect {|
    ((hand 4) (t.pending_draws 0) (t.turn 1) (top_unchanged true))
    |}]
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
      print_s [%message "MISMATCH" (parsed : Rule.t list) (expected : Rule.t list)]
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
    ("List.length rules" 12)
    ("List.length rules" 11)
    (e
     "line 1: unknown preset 'nonsense mode' after 'use' (available: standard, stacking, draw until playable, stacking with draw until playable)")
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
      ~action:(Play { card_id = 720; declared_color = None })
    |> Or_error.ok_exn
  in
  let mid_stack_draw = Rule_engine.apply_action rules t ~player_id:0 ~action:Draw in
  print_s
    [%message
      "mid-stack" (t.stacking_value : Card.Value.t option)
        (Or_error.is_error mid_stack_draw : bool)];
  let t =
    Rule_engine.apply_action rules t ~player_id:0
      ~action:(Play { card_id = 721; declared_color = None })
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
      ~action:(Play { card_id = 730; declared_color = None })
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
      ~action:(Play { card_id = 740; declared_color = None })
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
      ~action:(Play { card_id = 750; declared_color = Some Blue })
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
    Rule_engine.apply_action rules t
      ~player_id:0 ~action:(Play { card_id = 700; declared_color = None })
    |> Or_error.ok_exn
  in
  let t =
    Rule_engine.apply_action rules t
      ~player_id:0 ~action:(Play { card_id = 701; declared_color = None })
    |> Or_error.ok_exn
  in
  let t = Rule_engine.apply_action rules t ~player_id:0 ~action:Pass |> Or_error.ok_exn in
  print_s
    [%message
      (t.turn : int)
        (t.stacking_value : Card.Value.t option)
        (List.length (Player.get_hand (List.nth_exn t.players 0)) : int)];
  [%expect {|
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
  [%expect {|
    (rules
     (((id 1) (priority 50) (condition Always) (actions ((Mutate AdvanceTurn))))
      ((id 2) (priority 50) (condition Always) (actions ((Mutate AdvanceTurn))))))
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
  [%expect {|
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
        "rule \"red reverse\" fires when a card is played but has no 'play the card' effect - the card will stay in the hand"))))
    (warnings
     (((rule_name "play reverse") (kind Missing_advance)
       (message
        "rule \"play reverse\" plays the card but has no 'advance turn' effect - the turn will never end"))))
    |}]
;;

let%expect_test "presets and mid-stack rules produce no lint warnings" =
  List.iter
    [ "standard"; "stacking"; "draw until playable"; "stacking with draw until playable" ]
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
