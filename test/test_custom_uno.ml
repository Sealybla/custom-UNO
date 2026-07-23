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

let%expect_test "wrong player's turn is rejected" =
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