open! Core
open! Async

module Queued_request = struct
  type t =
    { player_name : string
    ; action : Action.Client_to_server.t
    ; enqueued_at : Time_ns.t
    ; from_timer : bool (* enqueued by a turn timer, not a real client *)
    }
end

module Client_connection = struct
  type t =
    { name : string
    ; writer : Action.Server_to_client.t Pipe.Writer.t
    ; mutable is_bot : bool
    }
end

(* an isolated lobby/game: its own players, ruleset, and engine loop *)
module Room = struct
  type t =
    { code : string
    ; clients : Client_connection.t String.Table.t
    ; mutable game_state : Game_state.t option
    ; mutable ruleset : Rule_engine.Ruleset.t
    ; mutable rules_text : string (* last submitted text; "" = never set *)
    ; mutable hand_size : int (* cards dealt per player; `deal N cards` sets it *)
    ; mutable turn_timer : int
      (* seconds before the server plays for a stalled human; 0 = never.
         `turn timer N seconds` / `turn timer off` set it per room *)
    ; request_writer : Queued_request.t Pipe.Writer.t
    ; mutable action_seq : int (* bumped per applied action; stales timers *)
    ; mutable autopilot : string option (* player whose turn timed out *)
    ; mutable auto_passes : int (* consecutive server-made formality passes *)
    ; ready : String.Hash_set.t (* lobby members who clicked ready *)
    ; bots : String.Hash_set.t
      (* bots somebody deliberately added, as opposed to a seat a bot took
         over when its player dropped mid-game. The difference matters at
         game over: added bots stay for the rematch, takeovers do not. *)
    ; mutable last_winner : string option (* winner of this room's last game *)
    }
end

module Connection_state = struct
  type t =
    { mutable player_name : string option
    ; mutable room : Room.t option
    }
end

type t =
  { rooms : Room.t String.Table.t
  ; default_ruleset : Rule_engine.Ruleset.t
  ; default_hand_size : int
  ; default_turn_timer : int
  ; random : Random.State.t
  }

let request_queue_size_budget = 1024

(* Humans and bots share one table, so a room full of bots turns people away
   just like a room of players. 10 is official UNO's table size and kind to
   the deck: 108 cards minus 10 seven-card hands and the flipped top still
   leaves a 37-card draw pile. Past ~15 players the deal itself runs out of
   cards and game creation fails, so the lobby refuses long before that. *)
let max_participants = 10

(* room-wide broadcast *)
let broadcast (room : Room.t) event =
  Hashtbl.iter room.clients ~f:(fun client ->
    if not (Pipe.is_closed client.writer)
    then Pipe.write_without_pushback client.writer event)
;;

(* a bot is always willing to play, so it never holds up the ready gate *)
let is_bot_name (room : Room.t) name =
  match Hashtbl.find room.clients name with
  | Some c -> c.Client_connection.is_bot
  | None -> false
;;

let human_count (room : Room.t) =
  Hashtbl.count room.clients ~f:(fun c -> not c.Client_connection.is_bot)
;;

(* the lobby roster with ready flags, who is a bot, and the reigning champion *)
let lobby_event (room : Room.t) =
  let names = Hashtbl.keys room.clients in
  Action.Server_to_client.Lobby_updated
    { players = names
    ; ready_players =
        List.filter names ~f:(fun n ->
          Hash_set.mem room.ready n || is_bot_name room n)
    ; bot_players = List.filter names ~f:(is_bot_name room)
    ; last_winner = room.last_winner
    }
;;

let player_id_of_name state name =
  List.find_map state.Game_state.players ~f:(fun p ->
    if String.equal (Player.get_name p) name
    then Some (Player.get_id p)
    else None)
;;

let name_of_player_id state id =
  match List.nth state.Game_state.players id with
  | Some p -> Some (Player.get_name p)
  | None -> None
;;

let hand_of_player state player =
  List.filter_map (Player.get_hand player) ~f:(fun card_id ->
    Game_state.Card_registry.find state.Game_state.card_registry card_id
    |> Or_error.ok)
;;

let hand_counts_event (state : Game_state.t) =
  Action.Server_to_client.Hand_counts
    { counts =
        List.map state.players ~f:(fun p ->
          Player.get_name p, List.length (Player.get_hand p))
    }
;;

let send_hands (room : Room.t) state =
  List.iter state.Game_state.players ~f:(fun player ->
    match Hashtbl.find room.clients (Player.get_name player) with
    | None -> ()
    | Some client ->
      let hand = hand_of_player state player in
      (* asked per player, because with jump-in enabled someone who is not
         the current player may still have a legal move *)
      let playable_ids, swap_target_ids =
        Rule_engine.playable_and_swap_ids
          room.ruleset
          state
          ~player_id:(Player.get_id player)
      in
      if not (Pipe.is_closed client.writer)
      then
        Pipe.write_without_pushback
          client.writer
          (Action.Server_to_client.Hand_updated
             { your_hand = hand; playable_ids; swap_target_ids }))
;;

(* current player + whether a pass is legal + any open stack's value; sent
   after every action so the UI can keep the pass button honest *)
let turn_changed_event (room : Room.t) (state : Game_state.t) =
  Action.Server_to_client.Turn_changed
    { current_player_name =
        Option.value (name_of_player_id state state.Game_state.turn) ~default:""
    ; can_pass = Rule_engine.pass_available room.ruleset state
    ; stack_value = state.Game_state.stacking_value
    ; uno_race = Option.is_some state.Game_state.uno_vulnerable
    }
;;

let broadcast_game_started (room : Room.t) state =
  let player_names = List.map state.Game_state.players ~f:Player.get_name in
  let current_player_name =
    Option.value (name_of_player_id state state.Game_state.turn) ~default:""
  in
  let stacking_enabled = Rule_engine.Ruleset.uses_stacking room.ruleset in
  List.iter state.Game_state.players ~f:(fun player ->
    match Hashtbl.find room.clients (Player.get_name player) with
    | None -> ()
    | Some client ->
      if not (Pipe.is_closed client.writer)
      then
        Pipe.write_without_pushback
          client.writer
          (Action.Server_to_client.Game_started
             { your_hand = hand_of_player state player
             ; top_card = state.Game_state.top_card
             ; current_color = state.Game_state.current_color
             ; player_names
             ; current_player_name
             ; pending_draws = state.Game_state.pending_draws
             ; stacking_enabled
             }));
  (* Game_started carries the hand but not what is playable; send that too so
     the opening player sees highlights before anyone has acted *)
  send_hands room state;
  broadcast room (hand_counts_event state);
  broadcast room (turn_changed_event room state)
;;

(* Chooses an action for a bot-controlled player: continue an open stack or
   pass; stack a +2/+4 onto a pending penalty or draw it; otherwise play the
   first valid card in hand (declaring a real color for wilds) or draw. *)
let bot_action (state : Game_state.t) player_name =
  let fallback = Action.Client_to_server.Draw in
  (* a standing swap target rides along on every bot play: rules that don't
     swap ignore it, and a chosen-swap rule gets the strategic pick - the
     smallest hand that isn't the bot's own *)
  let swap_with =
    List.filter state.Game_state.players ~f:(fun p ->
      not (String.Caseless.equal (Player.get_name p) player_name))
    |> List.min_elt ~compare:(fun a b ->
         Int.compare
           (List.length (Player.get_hand a))
           (List.length (Player.get_hand b)))
    |> Option.map ~f:Player.get_name
  in
  let play_card hand (card : Card.t) =
    let declared_color =
      match card.Card.value with
      | Wild | Wild4 ->
        (* a wild's own color is NoColor, so declare a real one from hand *)
        let color =
          List.find_map hand ~f:(fun c ->
            match c.Card.color with
            | NoColor -> None
            | color -> Some color)
          |> Option.value ~default:Card.Color.Red
        in
        Some color
      | _ -> None
    in
    Action.Client_to_server.Play
      { card_id = Card.get_id card; declared_color; swap_with }
  in
  match player_id_of_name state player_name with
  | None -> fallback
  | Some player_id ->
    (match List.nth state.Game_state.players player_id with
     | None -> fallback
     | Some player ->
       let hand = hand_of_player state player in
       (match state.Game_state.stacking_value with
        | Some v ->
          (* mid-stack: only another card of the stacked value continues;
             otherwise pass to close the stack *)
          (match
             List.find hand ~f:(fun c -> Card.Value.equal (Card.get_value c) v)
           with
           | Some card -> play_card hand card
           | None -> Action.Client_to_server.Pass)
        | None ->
          let candidate =
            if state.Game_state.pending_draws > 0
            then
              (* only another +2/+4 dodges a pending penalty; drawing (the
                 fallback) accepts it *)
              List.find hand ~f:(fun c ->
                match c.Card.value with
                | Wild4 -> true
                | Plus ->
                  Game_rules.is_valid_play
                    ~top_card:state.Game_state.top_card
                    ~played_card:c
                    ~current_color:state.Game_state.current_color
                | _ -> false)
            else
              Game_rules.choose_card
                ~hand
                ~top_card:state.Game_state.top_card
                ~current_color:state.Game_state.current_color
          in
          (match candidate with
           | None -> fallback
           | Some card -> play_card hand card)))
;;

let bot_move_delay = Time_ns.Span.of_sec 5.0
let default_turn_timer_s = 20
let countdown_seconds = 5
let autopilot_delay = Time_ns.Span.of_sec 1.5

(* run f later unless another action lands (or the game ends) first *)
let after_if_idle (room : Room.t) span ~f =
  let seq = room.action_seq in
  don't_wait_for
    (let%map () = Clock_ns.after span in
     match room.game_state with
     | None -> ()
     | Some state ->
       if Int.equal room.action_seq seq
          && Option.is_none state.Game_state.winner
       then f state)
;;

let enqueue_auto_action (room : Room.t) (state : Game_state.t) player_name =
  don't_wait_for
    (Pipe.write_if_open
       room.request_writer
       { Queued_request.player_name
       ; action = bot_action state player_name
       ; enqueued_at = Time_ns.now ()
       ; from_timer = true
       })
;;

(* Arm whatever drives the seat whose turn it is: bots move after a short
   delay; a human gets a room-wide countdown warning near the deadline and
   an auto-played move at it, after which their turn is finished at bot
   pace until it moves on. After a rejection only re-arm the automated
   drivers - an idle human's original timers are still pending. *)
let schedule_turn_driver ?(after_rejection = false) (room : Room.t) state =
  match name_of_player_id state state.Game_state.turn with
  | None -> ()
  | Some current ->
    (match Hashtbl.find room.clients current with
     | None -> ()
     | Some client when client.is_bot ->
       after_if_idle room bot_move_delay ~f:(fun st ->
         Core.print_s
           [%message
             "Bot execution triggered" (room.code : string) (current : string)];
         enqueue_auto_action room st current)
     | Some _ ->
       if Option.exists room.autopilot ~f:(String.equal current)
       then after_if_idle room autopilot_delay ~f:(fun st ->
         enqueue_auto_action room st current)
       else if not after_rejection
       then (
         room.autopilot <- None;
         let timer_s = room.turn_timer in
         if timer_s > 0
         then (
           (* short timers shrink the warning window so it never precedes
              the turn itself *)
           let warn_s = Int.min countdown_seconds (timer_s - 1) in
           if warn_s > 0
           then
             after_if_idle
               room
               (Time_ns.Span.of_int_sec (timer_s - warn_s))
               ~f:(fun _ ->
                 broadcast
                   room
                   (Action.Server_to_client.Turn_countdown
                      { player_name = current; seconds = warn_s }));
           after_if_idle room (Time_ns.Span.of_int_sec timer_s) ~f:(fun st ->
             Core.print_s
               [%message
                 "Turn timed out; playing for the player"
                   (room.code : string)
                   (current : string)];
             room.autopilot <- Some current;
             enqueue_auto_action room st current))))
;;

(* The seat whose turn it is either has real choices - broadcast the turn
   and arm its driver - or can only click done, a formality the server
   performs at once (e.g. mid-stack with nothing left to continue). The
   cap stops a pathological all-pass ruleset from looping forever. *)
let drive_or_auto_pass (room : Room.t) state =
  match name_of_player_id state state.Game_state.turn with
  | None -> ()
  | Some current ->
    if Rule_engine.only_pass_available room.ruleset state
       && room.auto_passes < List.length state.Game_state.players
    then (
      room.auto_passes <- room.auto_passes + 1;
      Core.print_s
        [%message
          "Auto-pass: only legal move" (room.code : string) (current : string)];
      don't_wait_for
        (Pipe.write_if_open
           room.request_writer
           { Queued_request.player_name = current
           ; action = Action.Client_to_server.Pass
           ; enqueued_at = Time_ns.now ()
           ; from_timer = true
           }))
    else (
      room.auto_passes <- 0;
      broadcast room (turn_changed_event room state);
      schedule_turn_driver room state)
;;

(* A bot that just played down to one card has to press the button like
   everyone else, or every bot seat would be a free catch. It calls after a
   beat, which is what leaves humans a real window to beat it to the press.
   The re-check on wake matters: by then somebody may already have caught it,
   in which case the window is shut and calling would be a fineable
   false alarm. *)
let maybe_bot_calls_uno (room : Room.t) (next_state : Game_state.t) =
  match next_state.uno_vulnerable with
  | None -> ()
  | Some player_id ->
    (match name_of_player_id next_state player_id with
     | None -> ()
     | Some player_name ->
       (match Hashtbl.find room.clients player_name with
        | Some client when client.is_bot ->
          don't_wait_for
            (let%map () = Clock_ns.after (Time_ns.Span.of_sec 2.0) in
             match room.game_state with
             | None -> ()
             | Some verified_state ->
               if Option.exists verified_state.Game_state.uno_vulnerable
                    ~f:(Int.equal player_id)
               then
                 Pipe.write_without_pushback
                   room.request_writer
                   { Queued_request.player_name
                   ; action = Action.Client_to_server.Call_uno
                   ; enqueued_at = Time_ns.now ()
                     (* server-generated, like the turn timer's moves: it
                        must not count as the player retaking their seat *)
                   ; from_timer = true
                   })
        | _ -> ()))
;;

(* A jump-in is an accepted play from someone who was not the current player.
   The turn leapt to them, so everyone from the seat whose turn it was up to
   (not including) the jumper lost their go. The regular skip diffing below
   cannot see this: it measures turns_advanced, and JumpToActor moves the
   turn without advancing it. *)
let broadcast_jump_in (room : Room.t) ~(before : Game_state.t) ~actor_id =
  (* announce the jumper first, then everyone they leapt over *)
  (match name_of_player_id before actor_id with
   | Some player_name ->
     broadcast room (Action.Server_to_client.Jumped_in { player_name })
   | None -> ());
  let num_players = List.length before.players in
  let dir = if Direction.equal before.direction Clockwise then 1 else -1 in
  let rec seats_passed idx acc =
    if Int.equal idx actor_id || List.length acc >= num_players
    then List.rev acc
    else seats_passed ((idx + dir + num_players) % num_players) (idx :: acc)
  in
  List.iter (seats_passed before.turn []) ~f:(fun idx ->
    match name_of_player_id before idx with
    | Some player_name ->
      broadcast room (Action.Server_to_client.Player_skipped { player_name })
    | None -> ())
;;

(* An UNO press never moves the turn and never triggers an ordinary draw, so
   it reports itself rather than going through the skip/forced-draw diffing
   below. Whoever gained cards paid a penalty; if nobody did, the call stood.
   [caught] separates "you sat on one card too long" from "you pressed it for
   no reason", which the UI phrases differently. *)
let broadcast_uno_result
  (room : Room.t)
  ~(before : Game_state.t)
  ~(after : Game_state.t)
  ~caller_name
  =
  let penalized =
    List.filter_mapi after.players ~f:(fun idx p ->
      let grew =
        Game_state.hand_size after idx - Game_state.hand_size before idx
      in
      if grew > 0 then Some (Player.get_name p, grew) else None)
  in
  match penalized with
  | [] ->
    broadcast
      room
      (Action.Server_to_client.Uno_called { player_name = caller_name })
  | penalized ->
    List.iter penalized ~f:(fun (player_name, count) ->
      broadcast
        room
        (Action.Server_to_client.Uno_penalty
           { player_name
           ; count
           ; caught = not (String.equal player_name caller_name)
           }))
;;

(* Compare the states around one action and broadcast what happened to whom:
   who was skipped, who was forced to draw, and direction flips. These are
   pure notifications - the UI turns them into splashes and seat badges. *)
let broadcast_notifications
  (room : Room.t)
  ~(before : Game_state.t)
  ~(after : Game_state.t)
  ~actor_id
  ~played
  =
  (* whole hands changing owners (swap/rotate rules) are their own
     spectacle, and a received hand must not read as a forced draw below *)
  let moves = Game_state.hand_moves ~before ~after ~played in
  let received_hand = Int.Set.of_list (List.map moves ~f:snd) in
  (if not (List.is_empty moves)
   then (
     let named =
       List.filter_map moves ~f:(fun (from, to_) ->
         match name_of_player_id after from, name_of_player_id after to_ with
         | Some a, Some b -> Some (a, b)
         | _ -> None)
     in
     if not (List.is_empty named)
     then broadcast room (Action.Server_to_client.Hands_moved { moves = named })));
  (* forced draws: a hand that grew without its owner acting, or the actor
     cashing out a pending +2/+4 penalty *)
  List.iteri after.players ~f:(fun idx p ->
    let grew =
      Game_state.hand_size after idx - Game_state.hand_size before idx
    in
    let forced =
      (not (Set.mem received_hand idx))
      &&
      if idx = actor_id
      then before.pending_draws > 0 && after.pending_draws = 0 && grew > 0
      else grew > 0
    in
    if forced
    then
      broadcast
        room
        (Action.Server_to_client.Forced_draw
           { player_name = Player.get_name p; count = grew }));
  (* skipped players: the turn moved 2+ seats in one action; everyone the
     turn passed over (except the actor) was skipped *)
  let advances = after.turns_advanced - before.turns_advanced in
  if advances >= 2
  then (
    let num_players = List.length after.players in
    let dir = if Direction.equal after.direction Clockwise then 1 else -1 in
    List.iter
      (List.init (advances - 1) ~f:(fun k -> k + 1))
      ~f:(fun k ->
        let idx =
          (actor_id + (dir * k) + (num_players * advances)) % num_players
        in
        if not (Int.equal idx actor_id)
        then (
          match name_of_player_id after idx with
          | Some player_name ->
            broadcast
              room
              (Action.Server_to_client.Player_skipped { player_name })
          | None -> ())));
  (* a direction flip is its own spectacle with 3+ players; with 2 the skip
     notification already tells the story *)
  if (not (Direction.equal before.direction after.direction))
     && List.length after.players > 2
  then
    broadcast
      room
      (Action.Server_to_client.Direction_changed
         { direction = after.direction })
;;

(* A bot occupies a seat exactly like a player: same table, same writer. It
   has no client on the other end, so its pipe is drained forever - without
   that, every broadcast would queue up in a pipe nobody ever reads. *)
let add_bot (room : Room.t) : unit Or_error.t =
  if Option.is_some room.game_state
  then Or_error.error_string "Cannot add bots once the game has started"
  else if Hashtbl.length room.clients >= max_participants
  then
    Or_error.errorf
      "Room is full (%d players max)"
      max_participants
  else (
    let name =
      let rec pick n =
        let candidate = sprintf "Bot %d" n in
        if Hashtbl.mem room.clients candidate then pick (n + 1) else candidate
      in
      pick 1
    in
    let reader, writer = Pipe.create () in
    don't_wait_for (Pipe.drain reader);
    Hashtbl.set
      room.clients
      ~key:name
      ~data:{ Client_connection.name; writer; is_bot = true };
    Hash_set.add room.bots name;
    Core.print_s [%message "Bot added" (room.code : string) (name : string)];
    Ok ())
;;

(* drops the most recently added bot, so the button is a plain counter *)
let remove_bot (room : Room.t) : unit Or_error.t =
  if Option.is_some room.game_state
  then Or_error.error_string "Cannot remove bots once the game has started"
  else (
    match
      List.sort (Hash_set.to_list room.bots) ~compare:String.compare
      |> List.last
    with
    | None -> Or_error.error_string "There are no bots to remove"
    | Some name ->
      (match Hashtbl.find room.clients name with
       | Some c -> Pipe.close c.writer
       | None -> ());
      Hashtbl.remove room.clients name;
      Hash_set.remove room.bots name;
      Hash_set.remove room.ready name;
      Ok ())
;;

(* A room with no HUMANS and no running game can be forgotten - bots alone
   must not keep it alive, or every abandoned lobby with a bot in it would
   leak a room and its engine loop. *)
let maybe_remove_room t (room : Room.t) =
  if human_count room = 0 && Option.is_none room.game_state
  then (
    Hashtbl.iter room.clients ~f:(fun c ->
      if not (Pipe.is_closed c.writer) then Pipe.close c.writer);
    Hashtbl.clear room.clients;
    Hash_set.clear room.bots;
    Hash_set.clear room.ready;
    Hashtbl.remove t.rooms room.code;
    Pipe.close room.request_writer;
    Core.print_s [%message "Room closed" (room.code : string)])
;;

(* per-room engine loop pulling actions off the room's pipe *)
let start_engine_loop t (room : Room.t) request_reader =
  don't_wait_for
    (Pipe.iter_without_pushback
       request_reader
       ~f:(fun { Queued_request.player_name; action; enqueued_at = _; from_timer }
          ->
         Core.print_s
           [%message
             "Processing Action"
               (room.code : string)
               (player_name : string)
               (action : Action.Client_to_server.t)];
         (* the player acting for themselves takes their seat back *)
         if (not from_timer)
            && Option.exists room.autopilot ~f:(String.equal player_name)
         then room.autopilot <- None;
         match room.game_state with
         | None -> ()
         | Some current_state ->
           (match player_id_of_name current_state player_name with
            | None -> ()
            | Some player_id ->
              (match
                 Rule_engine.apply_action
                   room.ruleset
                   current_state
                   ~player_id
                   ~action
               with
               | Error e ->
                 Core.print_s
                   [%message
                     "Rejected action" (player_name : string) (e : Error.t)];
                 (* tell the player who clicked; nobody else needs to know *)
                 (match Hashtbl.find room.clients player_name with
                  | Some client when not (Pipe.is_closed client.writer) ->
                    Pipe.write_without_pushback
                      client.writer
                      (Action.Server_to_client.Action_rejected
                         { reason = Error.to_string_hum e })
                  | _ -> ());
                 (* a bot or autopilot whose move was rejected must get
                    another shot, or its seat would freeze the game *)
                 schedule_turn_driver ~after_rejection:true room current_state
               | Ok next_state ->
                 room.action_seq <- room.action_seq + 1;
                 room.game_state <- Some next_state;
                 broadcast
                   room
                   (Action.Server_to_client.Pile_updated
                      { top_card = next_state.top_card
                      ; current_color = next_state.current_color
                      ; pending_draws = next_state.pending_draws
                      });
                 send_hands room next_state;
                 broadcast room (hand_counts_event next_state);
                 (* an UNO press is not a gameplay move; announcing it as one
                    would also announce who is catchable, which is exactly
                    the information the button is a race for *)
                 (match action with
                  | Action.Client_to_server.Call_uno ->
                    broadcast_uno_result
                      room
                      ~before:current_state
                      ~after:next_state
                      ~caller_name:player_name
                  | _ ->
                    (* an accepted move from someone who was not the current
                       player means they jumped in *)
                    if not
                         (Int.equal current_state.Game_state.turn player_id)
                    then
                      broadcast_jump_in
                        room
                        ~before:current_state
                        ~actor_id:player_id;
                    broadcast_notifications
                      room
                      ~before:current_state
                      ~after:next_state
                      ~actor_id:player_id
                      ~played:
                        (match action with
                         | Action.Client_to_server.Play { card_id; _ } ->
                           Some card_id
                         | _ -> None));
                 maybe_bot_calls_uno room next_state;
                 (* somebody emptied their hand on this action. With a
                    multi-winner finish mode the game carries on for the
                    lower places, so this is its own announcement rather
                    than a game-over. *)
                 List.iteri next_state.finished ~f:(fun i id ->
                   if i >= List.length current_state.Game_state.finished
                   then (
                     match name_of_player_id next_state id with
                     | Some player_name ->
                       broadcast
                         room
                         (Action.Server_to_client.Player_finished
                            { player_name; place = i + 1 })
                     | None -> ()));
                 (match next_state.winner with
                  | Some winner_id ->
                    (match name_of_player_id next_state winner_id with
                     | Some winner_name ->
                       let standings =
                         List.filter_map next_state.finished ~f:(fun id ->
                           name_of_player_id next_state id)
                       in
                       broadcast
                         room
                         (Action.Server_to_client.Game_over
                            { winner_name; standings });
                       room.game_state <- None;
                       room.last_winner <- Some winner_name;
                       (* bots somebody added stay for a rematch; seats a
                          bot only took over because its player dropped are
                          cleared out *)
                       Hashtbl.filter_inplace room.clients ~f:(fun client ->
                         (not client.is_bot)
                         || Hash_set.mem room.bots client.name);
                       broadcast room (lobby_event room);
                       maybe_remove_room t room
                     | None -> ())
                  | None -> drive_or_auto_pass room next_state)))))
;;

let code_alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ"

let generate_code t =
  let rec attempt () =
    let code =
      String.init 4 ~f:(fun _ ->
        code_alphabet.[Random.State.int t.random (String.length code_alphabet)])
    in
    if Hashtbl.mem t.rooms code then attempt () else code
  in
  attempt ()
;;

let create_room t =
  let code = generate_code t in
  let request_reader, request_writer = Pipe.create () in
  Pipe.set_size_budget request_writer request_queue_size_budget;
  let room =
    { Room.code
    ; clients = String.Table.create ()
    ; game_state = None
    ; ruleset = t.default_ruleset
    ; rules_text = ""
    ; hand_size = t.default_hand_size
    ; turn_timer = t.default_turn_timer
    ; request_writer
    ; action_seq = 0
    ; autopilot = None
    ; auto_passes = 0
    ; ready = String.Hash_set.create ()
    ; bots = String.Hash_set.create ()
    ; last_winner = None
    }
  in
  Hashtbl.set t.rooms ~key:code ~data:room;
  start_engine_loop t room request_reader;
  Core.print_s [%message "Room created" (code : string)];
  room
;;

let start
  ?(ruleset = Rule_engine.Ruleset.default)
  ?(hand_size = 7)
  ?(turn_timer = default_turn_timer_s)
  ~port
  ()
  =
  Core.print_endline
    (Core.sprintf "\n>>> Booting Uno Server on port %d..." port);
  Core.Out_channel.flush Core.stdout;
  let t =
    { rooms = String.Table.create ()
    ; default_ruleset = ruleset
    ; default_hand_size = hand_size
    ; default_turn_timer = turn_timer
    ; random = Random.State.make_self_init ()
    }
  in
  let in_room (state : Connection_state.t) =
    match state.player_name, state.room with
    | Some name, Some room -> Ok (name, room)
    | _ -> Or_error.error_string "Not in a room yet"
  in
  let implementations =
    Rpc.Implementations.create_exn
      ~implementations:
        [ Rpc.Rpc.implement Rpc_protocol.create_room_rpc (fun _state () ->
            let room = create_room t in
            return (Ok room.Room.code))
        ; Rpc.Rpc.implement
            Rpc_protocol.join_lobby_rpc
            (fun state { Rpc_protocol.Join_query.code; player_name = name } ->
               let code = String.uppercase (String.strip code) in
               match Hashtbl.find t.rooms code with
               | None ->
                 return
                   (Or_error.error_string
                      "No room with that code (it may have closed)")
               | Some room ->
                 if Option.is_some room.game_state
                 then
                   return
                     (Or_error.error_string
                        "Cannot join: a game is in progress in this room")
                 else if String.is_empty (String.strip name)
                 then return (Or_error.error_string "Invalid name")
                 else (
                   match state.Connection_state.player_name with
                   | Some _ ->
                     return
                       (Or_error.error_string
                          "Already registered on this connection")
                   | None ->
                     if Hashtbl.mem room.clients name
                     then
                       return
                         (Or_error.error_string
                            "Username already taken in this room")
                     else if Hashtbl.length room.clients >= max_participants
                     then
                       (* bots occupy seats too, so a room full of them
                          turns people away just like a room of players *)
                       return
                         (Or_error.errorf
                            "Room is full (%d players max) - remove a bot to \
                             make space"
                            max_participants)
                     else (
                       state.player_name <- Some name;
                       state.room <- Some room;
                       Core.print_s
                         [%message
                           "Lobby Registration"
                             (room.code : string)
                             (name : string)];
                       broadcast room (lobby_event room);
                       return (Ok ()))))
        ; Rpc.Pipe_rpc.implement
            Rpc_protocol.game_stream_rpc
            (fun state () ->
               match in_room state with
               | Error e -> return (Error e)
               | Ok (name, room) ->
                 if Option.is_some room.game_state
                 then
                   return
                     (Error
                        (Error.of_string
                           "Access denied: Game is already in progress!"))
                 else (
                   let reader, writer = Pipe.create () in
                   let connection =
                     { Client_connection.name; writer; is_bot = false }
                   in
                   Hashtbl.set room.clients ~key:name ~data:connection;
                   (* everyone in the room learns about the newcomer *)
                   broadcast room (lobby_event room);
                   return (Ok reader)))
        ; Rpc.Rpc.implement Rpc_protocol.get_state_rpc (fun state () ->
            match in_room state with
            | Error e -> return (Error e)
            | Ok (name, room) ->
              let lobby_snapshot () =
                lobby_event room
                :: (if String.is_empty room.rules_text
                    then []
                    else
                      (* empty player_name marks a snapshot, not a fresh edit *)
                      [ Action.Server_to_client.Rules_updated
                          { player_name = ""
                          ; num_rules = List.length room.ruleset
                          ; rules_text = room.rules_text
                          }
                      ])
              in
              (match room.game_state with
               | None -> return (Ok (lobby_snapshot ()))
               | Some game ->
                 (match
                    List.find game.Game_state.players ~f:(fun p ->
                      String.equal (Player.get_name p) name)
                  with
                  | None -> return (Ok (lobby_snapshot ()))
                  | Some player ->
                    let current_player_name =
                      Option.value
                        (name_of_player_id game game.Game_state.turn)
                        ~default:""
                    in
                    return
                      (Ok
                         [ Action.Server_to_client.Game_started
                             { your_hand = hand_of_player game player
                             ; top_card = game.Game_state.top_card
                             ; current_color = game.Game_state.current_color
                             ; player_names =
                                 List.map game.Game_state.players ~f:Player.get_name
                             ; current_player_name
                             ; pending_draws = game.Game_state.pending_draws
                             ; stacking_enabled =
                                 Rule_engine.Ruleset.uses_stacking room.ruleset
                             }
                           (* Game_started has no playable ids, so a client
                              rebuilding from this snapshot would think
                              nothing was playable until the next action *)
                         ; (let playable_ids, swap_target_ids =
                              Rule_engine.playable_and_swap_ids
                                room.ruleset
                                game
                                ~player_id:(Player.get_id player)
                            in
                            Action.Server_to_client.Hand_updated
                              { your_hand = hand_of_player game player
                              ; playable_ids
                              ; swap_target_ids
                              })
                         ; hand_counts_event game
                         ; turn_changed_event room game
                         ]))))
        ; Rpc.Rpc.implement Rpc_protocol.submit_rules_rpc
            (fun state rules_text ->
               match in_room state with
               | Error e -> return (Error e)
               | Ok (player_name, room) ->
                 if Option.is_some room.game_state
                 then
                   return
                     (Or_error.error_string
                        "Cannot change rules while a game is in progress")
                 else (
                   match Rule_parser.parse_ruleset_full rules_text with
                   | Error e -> return (Error e)
                   | Ok { rules; hand_size; turn_timer } ->
                     room.ruleset <- rules;
                     room.rules_text <- rules_text;
                     (* absent settings mean back to the defaults, so stale
                        ones never outlive the text that set them *)
                     room.hand_size
                     <- Option.value hand_size ~default:t.default_hand_size;
                     room.turn_timer
                     <- Option.value turn_timer ~default:t.default_turn_timer;
                     let num_rules = List.length rules in
                     Core.print_s
                       [%message
                         "Rules updated"
                           (room.code : string)
                           (player_name : string)
                           (num_rules : int)];
                     broadcast
                       room
                       (Action.Server_to_client.Rules_updated
                          { player_name; num_rules; rules_text });
                     return (Ok ())))
        ; Rpc.Rpc.implement Rpc_protocol.take_action_rpc (fun state action ->
            match in_room state with
            | Error e -> return (Error e)
            | Ok (player_name, room) ->
              let queued =
                { Queued_request.player_name
                ; action
                ; enqueued_at = Time_ns.now ()
                ; from_timer = false
                }
              in
              let%map () = Pipe.write_if_open room.request_writer queued in
              Ok ())
        ; Rpc.Rpc.implement Rpc_protocol.start_game_rpc (fun state () ->
            match in_room state with
            | Error e -> return (Error e)
            | Ok (_name, room) ->
              if Option.is_some room.game_state
              then return (Or_error.error_string "Game already in progress")
              else (
                let player_names = Hashtbl.keys room.clients in
                let not_ready =
                  List.filter player_names ~f:(fun name ->
                    (not (Hash_set.mem room.ready name))
                    && not (is_bot_name room name))
                in
                if List.length player_names < 2
                then return (Or_error.error_string "Need at least 2 players")
                else if not (List.is_empty not_ready)
                then
                  return
                    (Or_error.errorf
                       "Waiting for %s to ready up"
                       (String.concat ~sep:", " not_ready))
                else if room.hand_size * List.length player_names + 1 > 108
                then
                  return
                    (Or_error.errorf
                       "Cannot deal %d cards to %d players - the deck only \
                        has 108"
                       room.hand_size
                       (List.length player_names))
                else (
                  match
                    Game_state.create
                      ~player_names
                      ~hand_size:room.hand_size
                      ()
                  with
                  | Error e -> return (Error e)
                  | Ok initial_state ->
                    room.game_state <- Some initial_state;
                    room.autopilot <- None;
                    room.auto_passes <- 0;
                    (* a rematch needs everyone to ready up again *)
                    Hash_set.clear room.ready;
                    broadcast_game_started room initial_state;
                    (* the first player's turn timer starts now *)
                    drive_or_auto_pass room initial_state;
                    return (Ok ()))))
        ; Rpc.Rpc.implement Rpc_protocol.set_bots_rpc (fun state add ->
            match in_room state with
            | Error e -> return (Error e)
            | Ok (_player_name, room) ->
              let result = if add then add_bot room else remove_bot room in
              (match result with
               | Error _ as e -> return e
               | Ok () ->
                 broadcast room (lobby_event room);
                 return (Ok ())))
        ; Rpc.Rpc.implement Rpc_protocol.set_ready_rpc (fun state is_ready ->
            match in_room state with
            | Error e -> return (Error e)
            | Ok (player_name, room) ->
              if Option.is_some room.game_state
              then
                return
                  (Or_error.error_string "Game already in progress")
              else (
                if is_ready
                then Hash_set.add room.ready player_name
                else Hash_set.remove room.ready player_name;
                broadcast room (lobby_event room);
                return (Ok ())))
        ]
      ~on_unknown_rpc:`Close_connection
      ~on_exception:Log_on_background_exn
  in
  let%map tcp_server =
    Rpc.Connection.serve
      ~implementations
      ~initial_connection_state:(fun _addr _conn ->
        let state = { Connection_state.player_name = None; room = None } in
        don't_wait_for
          (let%bind () = Rpc.Connection.close_finished _conn in
           match state.Connection_state.player_name, state.room with
           | Some name, Some room ->
             if Option.is_some room.game_state
             then (
               match Hashtbl.find room.clients name with
               | None -> ()
               | Some client ->
                 client.is_bot <- true;
                 Core.print_s
                   [%message
                     "Player dropped mid-game. Bot activated."
                       (room.code : string)
                       (name : string)];
                 if Hashtbl.for_all room.clients ~f:(fun c -> c.is_bot)
                 then (
                   (* every seat is now a bot: nobody is left to play for,
                      so the game ends and the room can be forgotten *)
                   room.game_state <- None;
                   Hashtbl.clear room.clients;
                   Hash_set.clear room.ready;
                   Core.print_s
                     [%message
                       "All players left. Game abandoned."
                         (room.code : string)];
                   maybe_remove_room t room)
                 else (
                   match room.game_state with
                   | Some game
                     when Option.equal
                            String.equal
                            (name_of_player_id game game.Game_state.turn)
                            (Some name) ->
                     schedule_turn_driver room game
                   | _ -> ()))
             else (
               Hashtbl.remove room.clients name;
               Hash_set.remove room.ready name;
               Core.print_s
                 [%message
                   "Player left the lobby"
                     (room.code : string)
                     (name : string)];
               broadcast room (lobby_event room);
               maybe_remove_room t room);
             Deferred.unit
           | _ -> Deferred.unit);
        state)
      ~where_to_listen:(Tcp.Where_to_listen.of_port port)
      ()
  in
  Core.print_endline ">>> SUCCESS: TCP socket listening. Ready for players.";
  Core.Out_channel.flush Core.stdout;
  tcp_server
;;
