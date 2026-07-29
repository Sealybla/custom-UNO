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

let%expect_test "engine processes a draw" =
  let t = make_state () in
  let t' =
    Rule_engine.apply_action Rule_engine.Ruleset.default t ~player_id:0 ~action:Draw
    |> Or_error.ok_exn
  in
  let before = List.length (Player.get_hand (List.nth_exn t.players 0)) in
  let after = List.length (Player.get_hand (List.nth_exn t'.players 0)) in
  print_s [%message (before : int) (after : int) (t'.turn : int)];
  [%expect {| ((before 7) (after 8) (t'.turn 1)) |}]
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
  [%expect {| (winner (id 1) (moves 33)) |}]
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
    Rule_engine.apply_action Rule_engine.Ruleset.default t
      ~player_id:1 ~action:(Play { card_id = 201; declared_color = None })
    |> Or_error.ok_exn
  in
  print_s [%message "after stack" (t.pending_draws : int) (t.turn : int)];
  (* player 2 can't stack — draws the pending 4, pending resets to 0 *)
  let before = List.length (Player.get_hand (List.nth_exn t.players 2)) in
  let t =
    Rule_engine.apply_action Rule_engine.Ruleset.default t
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
    Rule_engine.apply_action Rule_engine.Ruleset.default t
      ~player_id:1 ~action:(Play { card_id = 300; declared_color = Some Red })
    |> Or_error.ok_exn
  in
  print_s [%message "after plus4 stack" (t.pending_draws : int) (t.turn : int)];
  (* player 2 can't continue — draws all 6, pending resets *)
  let before = List.length (Player.get_hand (List.nth_exn t.players 2)) in
  let t =
    Rule_engine.apply_action Rule_engine.Ruleset.default t
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

let%expect_test "draw until playable keeps drawing" =
  let top = { Card.color = Red; value = Five; id = 400 } in
  (* draw pile: two unplayable cards, then a playable one *)
  let d1 = { Card.color = Blue; value = Two; id = 401 } in   (* not red, not 5 *)
  let d2 = { Card.color = Green; value = Eight; id = 402 } in (* not red, not 5 *)
  let d3 = { Card.color = Red; value = Nine; id = 403 } in    (* red — playable *)
  let t =
    Game_state.for_testing
      ~player_hands:[ "a", []; "b", [] ]
      ~top_card:top
      ~draw_pile:[ d1; d2; d3 ]
      ~pending_draws:0
      ~turn:0
  in
  let before = List.length (Player.get_hand (List.nth_exn t.players 0)) in
  let t =
    Rule_engine.apply_action Rule_engine.Ruleset.draw_until_variant t
      ~player_id:0 ~action:Draw
    |> Or_error.ok_exn
  in
  let after = List.length (Player.get_hand (List.nth_exn t.players 0)) in
  print_s [%message "drew until playable" (before : int) (after : int) (t.turn : int)];
  [%expect {| ("drew until playable" (before 0) (after 3) (t.turn 0)) |}]
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

(* ---------- rule parser: round-trips against the hand-coded rulesets ---------- *)

let special_cards_text =
  {|
# special cards - shared by every variant
rule "play wild" priority 100:
  when card is wild and your turn
  do play the card, set color to declared, advance turn

rule "play plus two" priority 100:
  when card is plus two and your turn
  do play the card, set color from card, add 2 pending draws, advance turn

rule "play skip" priority 100:
  when card is skip and your turn
  do play the card, set color from card, skip next player

rule "play reverse" priority 100:
  when card is reverse and your turn
  do play the card, set color from card, reverse direction, advance turn

rule "take penalty" priority 90:
  when pending draws > 0 and your turn
  do apply pending draws, advance turn

rule "play plus four" priority 110:
  when card is plus four and your turn
  do play the card, set color to declared, add 4 pending draws, advance turn
|}
;;

let generic_play_text =
  {|
rule "play matching card" priority 10:
  when (card matches color or card matches value) and your turn
  do play the card, set color from card, advance turn
|}
;;

let draw_one_text =
  {|
rule "draw a card" priority 1:
  when player draws and your turn
  do draw 1 card, advance turn
|}
;;

let draw_until_text =
  {|
rule "draw until playable" priority 1:
  when player draws and your turn
  do draw until playable
|}
;;

let stacking_text =
  {|
rule "open stack" priority 10:
  when (card matches color or card matches value) and your turn
  do play the card, set color from card, open stack

rule "continue stack" priority 120:
  when continues stack and your turn
  do play the card, set color from card

rule "pass on stack" priority 120:
  when player passes and your turn
  do clear stack, advance turn
|}
;;

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

let%expect_test "parsed default ruleset equals hand-coded default" =
  check_against_hand_coded
    (special_cards_text ^ generic_play_text ^ draw_one_text)
    Rule_engine.Ruleset.default;
  [%expect {| parsed rules match the hand-coded ruleset |}]
;;

let%expect_test "parsed draw-until ruleset equals hand-coded variant" =
  check_against_hand_coded
    (special_cards_text ^ generic_play_text ^ draw_until_text)
    Rule_engine.Ruleset.draw_until_variant;
  [%expect {| parsed rules match the hand-coded ruleset |}]
;;

let%expect_test "parsed stacking ruleset equals hand-coded variant" =
  check_against_hand_coded
    (special_cards_text ^ stacking_text ^ draw_one_text)
    Rule_engine.Ruleset.stacking_variant;
  [%expect {| parsed rules match the hand-coded ruleset |}]
;;

let%expect_test "parsed stacking ruleset plays a real stacking turn" =
  let rules =
    Rule_parser.parse_ruleset (special_cards_text ^ stacking_text ^ draw_one_text)
    |> Or_error.ok_exn
  in
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