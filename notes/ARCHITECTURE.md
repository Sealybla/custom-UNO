# Custom UNO — Architecture

A multiplayer UNO server in OCaml where **the rules themselves are data**.
Players type rules into a browser editor, the server parses them into an
engine ruleset, and the game behaves accordingly. Nothing about UNO is
hard-coded into the turn loop.

> Scratch notes — this folder is gitignored. The tracked, user-facing spec
> for the rule language is `docs/rule-language.md`; this file documents the
> code.

---

## 1. Running it

```bash
dune build                       # build everything
dune runtest                     # expect tests (the whole suite)
dune exec custom-uno -- -port 8080
#   game RPC on 8080, web UI on 8081 (always port+1)
#   -rules FILE loads a ruleset at boot; unparseable = fatal, by design

./scripts/share.sh 8091          # public https link via a Cloudflare quick tunnel
dune exec uno-client             # terminal client (ready/start/draw/pass/uno/play/rules)
```

`dune utop lib` is the fastest way to poke at the engine directly — most of
the interesting logic is pure and needs no server.

---

## 2. Map of the repo

```
lib/                 the whole game; no I/O except server.ml
  card.ml            Color, Value, and a card = {color; value; id}
  player.ml          {id; name; hand} where hand is a list of card IDs
  direction.ml       Clockwise | Counter
  event.ml           what a player did, in engine terms
  action.ml          the wire protocol: Client_to_server / Server_to_client
  game_state.ml      the whole game as one immutable record + Effect
                     (official-UNO legality lives here too: is_valid_play,
                     matches_color, first_playable_card — used by bots and
                     draw effects. Formerly a separate game_rules.ml.)
  rule.ml            Condition / Rule — the rule AST
  rule_engine.ml     evaluation, the built-in rulesets, apply_action
  rule_parser.ml     text -> rules + settings, `use <preset>`, the linter
  presets.ml         canonical rule TEXT for every built-in ruleset
  accounts.ml        optional login + per-user saved rule "modes" (sexp file)
  rpc_protocol.ml    Async RPC definitions
  server.ml          rooms, the action queue, bots, turn timer, broadcasts

bin/
  main.ml            boots the RPC server + the HTTP server on port+1
  page.ml            THE ENTIRE WEB UI as one OCaml string literal (~2800 lines)
  web.ml             HTTP/JSON bridge: browser <-> RPC, and event -> JSON
  client.ml          terminal client

test/test_custom_uno.ml    ~3100 lines of expect tests
docs/rule-language.md      user-facing rule language reference
examples/*.rules           standalone rule files (untested — see §12)
scripts/share.sh           Cloudflare quick tunnel
```

---

## 3. The layering

```
   browser (page.ml, plain JS)            terminal (client.ml)
        |  HTTP + JSON polling                 |  Async RPC
        v                                      v
   web.ml  ──(RPC client on localhost)──>  server.ml
                                               |
                                    one Pipe per room, serialized
                                               v
                                        rule_engine.apply_action
                                               |
                        ┌──────────────────────┼──────────────────────┐
                        v                      v                      v
                  eval_condition          eval_action           update_uno_window
                   (Rule.Condition)    (Game_state.Effect)      (engine-owned)
                                               |
                                               v
                                     a NEW Game_state.t
```

The important structural fact: **`lib/` is pure except for `server.ml`.**
The engine is a function from `(ruleset, state, action)` to `state Or_error.t`.
That is why the tests can play whole games with no network.

---

## 4. Core data model

### `Card` / `Player` / `Direction`

Cards are `{color; value; id}` with a globally unique `id`. **Hands store IDs,
not cards** — `Player.hand : int list`. Resolution goes through
`Game_state.card_registry : Card.t Int.Map.t`. This keeps `Player.t` small
over the wire and makes card identity survive shuffles.

`Color` includes `NoColor`, which does double duty: it is a wild's own color
*and* "no color is currently in force". See §11.5 — this overload has already
caused one bug.

### `Game_state.t`

One immutable record threaded through everything:

| field | purpose |
|---|---|
| `players` | seats, in turn order; index = player id |
| `draw_pile` / `played_pile` | `played_pile` excludes `top_card` |
| `top_card` | the visible discard |
| `current_color` | the color in force (may differ from `top_card.color` after a wild) |
| `stacking_value` | `Some v` = a same-value stack is open |
| `direction` | Clockwise / Counter |
| `pending_draws` | accumulated +2/+4 penalty in the stacking variant |
| `drew_playable` | the player drew something playable and may play or pass |
| `turns_advanced` | monotonic; diffing it detects skips (see §9) |
| `turn` | whose turn (index into `players`) |
| `uno_vulnerable` | who can be caught for not calling UNO |
| `finished` | players who emptied their hand, **in finishing order** — the podium |
| `card_registry` | id -> card |
| `winner` | set by `CheckWinner` once the finish mode is satisfied; always `finished`'s head |

`finished` and `winner` are two different questions. `winner` answers "is the
game over"; `finished` answers "who is out, and in what order". Under the
default finish mode they move together, but with `play until one player is
left` the game keeps running with a non-empty `finished` and no `winner` yet
(see §11.6).

---

## 5. The rule engine — the heart

Three types define everything:

**`Event.t`** — what a player did, engine-side:
`CardPlayed | DrawRequested | PassRequested | UnoCalled`. `CardPlayed`
carries `declared_color` (the wild's choice) and `swap_with` (a resolved
target player, validated at event construction: exists, and isn't the actor).

**`Rule.Condition.t`** — a boolean expression over `(state, event)`, combined
with `And / Or / Not`. The leaves fall into four groups:

| group | leaves |
|---|---|
| the played card | `MatchesTopColor`, `MatchesTopValue`, `MatchesTopExactly`, `IsWildCard`, `IsSkip`, `IsReverse`, `IsPlusTwo`, `IsPlusFour`, `IsNumber n`, `IsCardColor c`, `IsActionCard`, `IsNumberCard` |
| the table | `ActiveColorIs c`, `TopCardIsNumber n`, `TopCardIsAction`, `DirectionIsClockwise`, `DrawPileLessThan n`, `PendingDrawsGreaterThan n`, `StackIsOpen`, `ContinuesStack` |
| the actor | `IsPlayerTurn`, `HandSizeGreaterThan n`, `HandSizeEquals n`, `CallerHasUno`, `SomeoneElseHasUno` |
| other players | `AnyOpponentHandEquals n`, `AnyOpponentHandGreaterThan n` — some player *other than the actor*. `SomeoneElseHasUno` is different: it is window-based (true only while another player's open catch window — `uno_vulnerable` — belongs to someone other than the presser), not a hand-size test |
| the action kind | `IsDrawAction`, `IsPassAction`, `IsUnoCall`, `DrewPlayableCard`, `Always` |

**`Game_state.Effect.t`** — a state transition: `PlayTriggeringCard`,
`AddPendingDraws n`, `DrawAndDecide`, `AdvanceTurn`, `JumpToActor`,
`CheckWinner finish`, `MarkUnoCalled`, `PenalizeUnoTarget n`,
`SwapHandsWithNext`, `SwapHandsWithChosen`, `RotateHands`, `AllOthersDraw n`,
`ChosenPlayerDraws n`, `Reject msg`, …

A `Rule.t` is `{id; priority; condition; actions}` where `actions` is a plain
`Effect.t list`, applied in order — **the first effect that errors rejects the
whole action**, leaving the state untouched.

`Reject msg` is how a rule *forbids* something ("no going out on an action
card"). It is worth appreciating why refusal is an ordinary effect rather than
a separate kind of action: it composes. A rule can run three effects and then
reject, and it costs the AST nothing. An earlier design on this branch wrapped
every effect in an `Action_AST.Mutate | Reject` layer; folding refusal into
`Effect.t` deleted that layer with no loss of expressiveness.

### Resolution: highest priority wins, and *only* that rule runs

```
process_event rules state evt =
  sort rules by priority descending
  keep those whose condition holds
  match:
  | []            -> Error "Illegal move: no rule allows that right now"
  | winner :: _   -> run winner.actions, recursing on any chained events
```

**Exactly one rule fires per action.** This is the single most important
thing to understand about the codebase, and the source of most subtle bugs:

- A rule that wins a card play but forgets `play the card` silently swallows
  the click. (The linter in `rule_parser.ml` exists specifically for this.)
- Priority is the *only* arbitration mechanism. There is no "run all matching
  rules", no fallthrough, no explicit ordering beyond the number.

### Priority map of the built-ins

| priority | rules |
|---|---|
| 200 / 190 / 180 | UNO: call / catch / false-call |
| 130 | jump in (out-of-turn exact match) |
| 120 | continue stack, pass on stack |
| 110 | play +4 |
| 105 | take penalty (stacking) |
| 100 | wild, skip, reverse, +2 |
| 60 | seven-zero's 7 and 0 (add-on preset) |
| 50 | parser default when `priority` is omitted |
| 10 | generic play / open stack |
| 1 | draw, pass-after-draw |

The gaps are deliberate. Seven-zero sits at 60: above the generic play rule
(10) so 7s and 0s get their swap behavior, below the specials (100+) so
action cards keep theirs. Priority alone does not keep it out of open
stacks, though — a mid-stack 7 of a *different* value matches nothing at
120 — so both seven-zero rules also carry an explicit `not stack is open`.
Jump-in sits at 130, above the stack rules, because it has to be decided
before anything that assumes it is already your turn.

### `apply_action` — the one entry point

```ocaml
apply_action rules state ~player_id ~action =
  player   <- lookup player_id
  evt      <- event_of_client_action action
  state'   <- process_event rules state evt
  Ok (Game_state.update_uno_window state' ~actor_id ~event:evt)
```

Note the last line: the UNO catch window is maintained by the **engine**, not
by a rule. That is deliberate — rules are user-editable in the browser, so if
the window were a rule, a player could edit themselves into being permanently
uncatchable.

---

## 6. The rule language and parser

`rule_parser.ml` is a hand-written recursive-descent parser over a tiny
tokenizer. Grammar (full reference in `docs/rule-language.md`):

```
rule "name" [priority N]:
  when <condition>
  do <effect> [, <effect> ...]
```

Precedence is `not` > `and` > `or`, parentheses override.

Beyond plain parsing:

**`use <preset>`** expands to the canonical text in `presets.ml`. So
`use stacking` is literally equivalent to pasting the stacking ruleset.

**Override by name.** A later rule with the same name as an earlier one
*replaces it in place* rather than duplicating. This is what makes
`use standard` + one custom rule work as "the standard game, but…".

**Subtraction by name.** `remove rule "play plus four"` drops a rule from
everything defined *above* it, so it belongs after the `use` line it edits.
Removing a name nothing defined is an error that lists what exists. Note what
removal means given §5: the cards that rule powered become **unplayable**, not
free — no rule accepts them, so nothing does. Removal is positional like
redefinition, so a later rule of the same name re-adds it.

**Settings, not rules.** Some directives configure the game the rules run in
rather than reacting to an event, so they are lines of their own with no
`when`/`do`. The parser returns them beside the rules as a `Parsed.t`:

| directive | effect | bounds |
|---|---|---|
| `deal N cards` | starting hand size | 1–30, and `N × players + 1 ≤ 108` at start |
| `turn timer N seconds` / `turn timer off` | per-room autopilot delay | 5–300, or off |
| `play until …` | the finish mode (§11.6) | — |

**Two pre-scans, and their order matters.** `play until` is lifted out of the
token stream *before* anything else runs (`extract_finish`), because it has to
apply to preset rules that a later `use` pulls in — it becomes the `Finish.t`
payload baked into every `CheckWinner`. `deal` / `turn timer` stay in the main
token loop, since they are only ever hand-written. Tokens carry their line
number, so stripping `play until` early doesn't corrupt later error messages.

**Lint** (`parse_ruleset_checked`) returns warnings alongside the rules:
`Missing_play`, `Missing_advance`, `Missing_set_color`, `Missing_turn`, and
`Dead_rule` flag the footguns that follow from "only one rule fires". Warnings
never reject a ruleset; each carries an optional `fix` snippet so the editor
can offer one-click repair.

### `presets.ml` is the single source of truth for rule text

Nine presets, assembled from shared blocks (`base_specials`, `deferred_draws`,
`uno_rules`, `jump_in`, …):

- the 2×2 base matrix — `standard`, `stacking`, `draw until playable`,
  `stacking with draw until playable`
- each of those `with jump in` (four more)
- `seven zero`, which is **an add-on, not a variant**

Seven-zero is the pattern to copy for future options. Rather than doubling the
matrix again, it is a preset containing only two rules, and the lobby emits a
*second* `use seven zero` line after the base one. Eight variants became
sixteen the moment jump-in was folded into the matrix; the next feature should
not repeat that.

The lobby toggles and `use` both expand to this text, and expect tests assert
each parses to *exactly* its hand-coded `Rule_engine.Ruleset` twin.

**This dual representation is a deliberate redundancy, and it is load-bearing.**
Hand-coded rulesets are what the engine ships with; preset text is what users
see and edit. The round-trip tests are what stop them drifting.

---

## 7. Server

`server.ml` is the only stateful, effectful module.

### Rooms

Players create/join isolated rooms by 4-letter code (`Room.t`), each with its
own `clients`, `ruleset`, `game_state`, `ready` set, `bots` set, the mutable
settings a ruleset can override (`hand_size`, `turn_timer`) and — critically —
its own `Pipe.Writer.t` of `Queued_request.t`.

Room settings are *derived from the ruleset, held on the room*: submitting
rules writes `room.hand_size` / `room.turn_timer`, and a ruleset that omits a
directive resets that setting to the server default rather than leaving the
previous value behind. Without that reset, deleting `deal 9 cards` from the
editor would silently keep dealing nine.

**All actions for a room funnel through that one pipe and are processed one at
a time.** This is why there are no locks anywhere: concurrency is resolved by
queue order. "Who pressed UNO first" is simply "whose request was enqueued
first".

### `Queued_request.from_timer`

Distinguishes a real client click from a server-generated action (turn timer,
auto-pass, a bot's UNO call). A real click takes a player's seat back from
autopilot; a server-generated one must not.

### Bots, turn timer, autopilot

| mechanism | trigger | delay |
|---|---|---|
| bot move | seat is a bot | 5s |
| turn countdown broadcast | human, 5s before timeout | 15s |
| autopilot takeover | human turn times out | 20s |
| autopilot further moves, same turn | the timed-out turn continues (stack, drawn card) | 1.5s |

Autopilot covers only the remainder of the timed-out turn: it is cleared as
soon as the turn belongs to anyone else, so the player's next turn gets the
full timer again. Sustained absence is the disconnect path's job (bot
takeover), not autopilot's.
| bot UNO call | bot's hand hits 1 | 2s |
| auto-pass | pass is the *only* legal move | immediate |

`after_if_idle` stamps `room.action_seq` so a timer that fires after the
player already acted becomes a no-op — the standard fix for stale timers.

### Bots as lobby participants

Two different things are called "a bot", and `Room.bots` is what separates
them:

- a seat that *became* bot-driven because a human dropped or timed out
  (autopilot — the row above), and
- a bot somebody **added on purpose** from the lobby.

Only the second kind is in `room.bots`. The distinction earns its keep at game
over, where the server clears autopilot seats but must keep deliberately-added
bots so the rematch still has opponents.

| concern | how |
|---|---|
| capacity | `max_participants = 10`, counting humans and bots alike |
| ready gate | bots count as ready, so they never block Start |
| room reclamation | `human_count room = 0` frees the room after a 30s grace window (a page refresh empties a lobby for only a moment); bots alone don't keep it alive |
| a bot's event pipe | `Pipe.drain` on the reader — nothing consumes it, and unread events would accumulate forever |

The capacity rule is one constant on purpose. Humans and bots share the table,
so a room full of bots turns people away exactly like a room full of players —
and the refusal message says to remove a bot, because "room is full" is
baffling when you can see empty chairs.

### Mid-game reconnect

Joining a room with a game in progress is refused — **except** back into your
own abandoned seat. `join_lobby_rpc` matches the requested name
case-insensitively against the seated players, then checks the seat is actually
abandoned:

```ocaml
match Hashtbl.find room.clients canonical with
| None -> true                                  (* client gone entirely *)
| Some c -> c.is_bot || Pipe.is_closed c.writer (* on autopilot, or dead pipe *)
```

If the seat is still live you get *"X is still connected in this room"* rather
than a silent takeover — otherwise anyone could evict a player by typing their
name. Reconnecting broadcasts `Player_rejoined`; dropping broadcasts
`Player_dropped`, so the table can show who is on autopilot.

This is why the room-full check carries an `Option.is_none existing` guard
(where `existing` is a *caseless* scan of the seated names): retaking a seat
you already occupy adds nobody, so a full room must not block it.

### Notification diffing

The server compares state before/after each action to synthesize UI events it
would otherwise have no way to know about:

- **skips**: `turns_advanced` moved 2+ seats -> `Player_skipped` for each
  seat passed over
- **forced draws**: a hand grew without its owner acting -> `Forced_draw`
- **direction**: flipped, and 3+ players -> `Direction_changed`
- **hands moved**: whole hands changed owner (seven-zero) -> `Hands_moved`
  with the (from, to) pairs, so the table can animate the swap
- **UNO**: handled separately by `broadcast_uno_result`, since an UNO press
  moves no turn and the "penalty" is just someone's hand growing
- **jump-in**: `broadcast_jump_in`, since the turn moving *backwards* looks
  like nothing else in the protocol

---

## 8. The two clients

> Function-by-function walkthrough of `web.ml` and `client.ml`, and the case
> for keeping the terminal client at all: **`CLIENTS.md`**.

### Browser (`bin/page.ml` + `bin/web.ml`)

`page.ml` is **the entire web UI as one OCaml quoted string literal**
(`{html|...|html}`). HTML + CSS + vanilla JS, no framework, no build step, no
external assets.

⚠️ **The compiler validates none of it.** It is a string. This is the single
biggest hazard in the repo — see §13.

Internal structure (JS sections are marked with `/* ---------- … */`):
event reducer -> dirty flags -> targeted renderers -> flight animations.
The reducer mutates `state` and pushes *animation intents* into an `fx` array,
which the renderers consume; that split is what keeps animations from
fighting re-renders.

`web.ml` is a bridge, not a server: it holds an RPC *client* connection to
`server.ml` on localhost, buffers `Server_to_client.t` events per session, and
hands them to the browser as JSON via `/api/poll`. Sessions are keyed
`code/name` and expire after 8s of no polling.

HTTP routes: `/api/{create-room, join, leave, poll, state, start, ready, draw,
pass, uno, play, bots, rules, check-rules, preset-rules, login, me, mode-save,
mode-delete}`.

**Card legality is computed server-side.** `Rule_engine.playable_and_swap_ids`
simulates every card in the hand and returns the ids that are legal, plus the
subset that still needs a swap target chosen. The browser only highlights what
that list says. Legality was briefly duplicated in JS; with user-editable rules
that duplicate is guaranteed to drift, so the client no longer has an opinion.

### Terminal (`bin/client.ml`)

Speaks Async RPC directly. Commands: `ready`, `unready`, `start`, `draw`,
`pass`, `uno`, `play <id> [color] [swap target]`, `rules <file>`. Useful for
driving a second player without a browser.

---

## 9. One action, end to end

Playing a red 7:

1. Browser: `POST /api/play?card_id=42`
2. `web.ml` -> `take_action_rpc` -> `server.ml`
3. Server enqueues `{player_name; action; from_timer = false}` on the room pipe
4. Engine loop dequeues it, calls `Rule_engine.apply_action`
5. `event_of_client_action` -> `CardPlayed {player; card; declared_color;
   swap_with}` — the swap target is resolved and validated here
6. Rules sorted by priority; first whose condition holds wins
7. Its effects run in order (`fold_result`), producing a new `Game_state.t`;
   any effect returning an error discards the lot
8. `update_uno_window` recomputes who is catchable
9. Server stores the new state and broadcasts: `Pile_updated`, per-player
   `Hand_updated` (each carrying that player's freshly simulated
   `playable_ids`), `Hand_counts`, diffed notifications, `Turn_changed`
10. `web.ml` turns each into JSON; the browser's next `/api/poll` collects them
11. Reducer updates `state`, sets dirty flags, pushes animation intents
12. Renderers redraw only what changed

On rejection — step 6 finding no matching rule, or step 7 hitting a `Reject`
effect — only the acting player gets `Action_rejected`, and the state is
unchanged.

---

## 10. The variants

| variant | +2 / +4 | drawing | stacking |
|---|---|---|---|
| `default` | victim draws immediately, is skipped | draw 1; playable keeps turn (play or Done) | no |
| `stacking_variant` | adds to `pending_draws`; victim can stack or cash out | same | yes |
| `draw_until_variant` | immediate | one card per click, turn stays; only playing ends it (a dry deck turns the click into a pass) | no |
| `stacking_draw_until_variant` | deferred | one per click, blocked mid-stack | yes |

All four include `uno_rules`, and each has a `…_jump_in_variant` twin that
appends `jump_in_rules` — eight in total. Seven-zero is *not* in this table by
design: it is an add-on preset appended to any of the eight (see §6).

---

## 11. Feature notes

### 11.1 Stacking
`open stack` plays a card *without* `advance turn` and sets `stacking_value`.
While open, only `continues stack` (same value) or `pass on stack` match —
the specials all carry `not stack is open` to stay out of the way.

### 11.2 Pending draws
The stacking `+2/+4` bump a counter instead of dealing cards. `take penalty`
sits at priority 105 — *above* the specials — so a wild or skip can't dodge a
pending penalty.

### 11.3 The UNO button
Three rules at priorities 200/190/180: while somebody's catch window is
open, any press is a catch (the claim rule carries `not someone has uno`,
so even a presser who is themselves down to one card makes the catch);
otherwise a one-card press claims your own UNO, and a press with nothing
behind it fines you. The last rule matches *any* press, so a press never
falls through to a turn rule.

`Game_state.update_uno_window` decides who is catchable, in one assignment:

```ocaml
if is_gameplay_event event
then { t with uno_vulnerable =
         if hand_size t actor_id = 1 then Some actor_id else None }
else t   (* an UNO press is not a turn; the effects own the window there *)
```

That single line encodes "vulnerable until the next player acts", because only
the actor's own hand can shrink on their move — so at most one player is ever
catchable. Winning (hand 0) leaves nobody exposed, and acting twice mid-stack
keeps your own window open.

`has uno` deliberately means "holds one card", *not* "is catchable", so
pressing late is harmless rather than a fine.

### 11.4 Turn timer / autopilot
See §7. `only_pass_available` drives auto-pass; the counter caps it at one
lap so a pathological all-pass ruleset can't spin forever.

### 11.5 The wild opener
If the flipped starting card is a wild, `current_color = NoColor` and *nothing*
matched — the opening player couldn't play at all. Fixed by one shared
predicate:

```ocaml
let matches_color ~played_card ~current_color =
  match current_color with
  | NoColor -> true                 (* nobody has declared a color yet *)
  | color -> Card.Color.equal played_card.color color
```

Used by `Game_state.is_valid_play` and the engine's `MatchesTopColor`. The
browser no longer has its own copy — see §8.

### 11.6 Finish modes (`play until …`)

`Game_state.Finish.t` is `First_out | After of int | Last_standing`, and
`Finish.needed ~num_players` turns it into a count:

```ocaml
let all_but_one = Int.max 1 (num_players - 1) in
match t with
| First_out     -> 1
| Last_standing -> all_but_one
| After n       -> Int.min (Int.max 1 n) all_but_one
```

The clamping is the whole trick. `After n` can never demand more finishers
than can exist, so `play until 9 players finish` in a 3-player game is simply
last-standing rather than a game that can never end.

**How one line reaches every rule.** The parser expands `play the card` to
`[PlayTriggeringCard; CheckWinner finish]` — the winner check is not something
a rule author writes, it rides along with playing a card. So a single
`play until` line at the top of the file re-parameterizes every play rule in
the ruleset, including the ones a `use` pulled in, without touching their
text. That is why `finish` is threaded down through `parse_effect` rather than
stored beside the rules.

Two consequences ripple outward:

- **Everything that walks the table must skip finished players**, not just
  the turn: `Game_state.next_live_seat` (bounded — `tried >= num_players`
  bails out, since everyone can be out after a `Last_standing` finale) is
  shared by `advance_turn`, the +2/+4 target and the swap-with-next
  neighbor; rotations run over live seats only; `all others draw` skips
  finished hands; chosen-target effects reject finished targets; and
  `apply_action` rejects any action from a finished player outright, which
  also keeps the playability simulation (and so the UI highlights) blank
  for them. Bots pick swap targets from live opponents only.
- The server emits `Player_finished {name; place}` as each player goes out,
  `Game_over` carries the full `standings`, not just a winner, and both the
  reconnect replay and the `get_state` snapshot re-send the podium so a
  rejoiner greys out finished seats correctly.

### 11.7 Jump-in

One rule at priority 130: `card matches exactly and not card is action and
not your turn and not stack is open`. Number cards only, because the rule's
effect list is the generic play sequence — a jumped Skip/+2 would land as a
blank (write a custom rule spelling out the effects to allow action jumps).
Its effect list starts with `JumpToActor`, which moves `turn`
to whoever played *before* anything else runs — so the following
`PlayTriggeringCard` and `AdvanceTurn` operate from the jumper's seat, and
everyone between them and the previous player simply loses their go.

It is blocked mid-stack because barging into someone's open stack would strand
it with no way to close.

`MatchesTopExactly` compares printed color *and* value, so wilds never jump in
(they have no printed color to match).

### 11.8 Seven-zero

Two rules at priority 60 (§5), both guarded by `not stack is open` so a
mid-stack 7/0 cannot swap and strand the stack. The 7 uses
`SwapHandsWithChosen`, which rejects
with `Game_state.target_needed` when no target was declared; the playability
simulation catches that specific error to mark the card `Needs_target` rather
than illegal, which is how the UI knows to ask before sending the play.

Both rules list `play the card` first, and since that expands to include
`CheckWinner` (§11.6), going out on your last 7 wins *before* any hands move —
as in the real house rule. The ordering is not incidental; swapping the effect
order would hand your winning hand away.

---

## 12. Testing

`test/test_custom_uno.ml`, ~3100 lines of `ppx_expect` tests. Run
`dune runtest`; `dune promote` accepts diffs.

Coverage: deck/deal invariants, each special card, stacking turns, pending
draws, draw modes, the UNO button (call/catch/false-call/window/late press),
jump-in, seven-zero swaps and rotations, targeted draws, `Reject`, finish modes
(`Finish.needed` and `play until` parsing in any position), settings directives
and their bounds, the wild opener, parser round-trips (`Presets.*` vs
hand-coded rulesets), `use`/override/lint, and full games to completion.

`Game_state.for_testing` builds a state directly from hands + top card, which
is how most tests avoid dealing a real game.

**Known gaps:**
- `examples/*.rules` are loaded by *nothing* — no test, no code path. They can
  rot silently. (They currently parse and match the hand-coded rulesets; that
  was verified by hand, not by CI.)
- `bin/page.ml` has no automated validation at all.

---

## 13. Traps for future work

1. **`bin/page.ml` is a string literal — the compiler checks none of it.**
   A merge once left 8 unresolved conflict markers in it and `dune build`
   passed. Anything inside can be broken and still compile.

2. **`grep` treats `page.ml` as binary** (it contains non-UTF8 bytes) and
   silently prints nothing. **Always `grep -a` on that file.** This has
   already hidden real problems twice.

3. **Never let `| html}` (no space) appear inside the page literal** — it
   terminates the OCaml string. There is a comment at the top warning about it.

4. **Only one rule fires per action.** Adding a rule at the wrong priority
   doesn't "add behavior", it *replaces* whatever it outranks.

5. **Several conditions ignore the event entirely** — `PendingDrawsGreaterThan`,
   `IsPlayerTurn`, `StackIsOpen`, `Always`. They match *any* event, including an
   UNO press. This is exactly why the UNO rules sit at 180–200. Any future
   non-turn action needs the same treatment.

6. **`NoColor` means two things** (a wild's color, and "no color in force").
   A `current_color : Color.t option` would make the second case impossible to
   forget. Worth doing if it bites again.

7. **Rule text lives in two places** — hand-coded `Rule_engine.Ruleset.*` and
   `Presets.*` text. They are kept in sync only by the round-trip expect tests.
   Change one, run `dune runtest`.

8. **`from_timer` matters.** Server-generated actions must set it `true`, or
   they'll be mistaken for the player retaking their seat from autopilot.

9. **Warning 9 is disabled, and it is asymmetric.** Adding a field to a
   record type compiles *silently* everywhere the record is destructured, but
   is a hard error everywhere one is constructed. So a new field on a
   broadcast record like `Lobby_updated` builds clean while `web.ml` quietly
   drops it and the browser never sees it — whereas a new field on
   `Client_to_server.Play` fails the build immediately. Adding a *variant* is
   checked in both directions. **After adding a field to anything crossing the
   wire, grep the consumers by hand**; the compiler will not help you. This
   has bitten three times.

10. **Error strings are load-bearing in one place.** The playability
    simulation distinguishes "needs a swap target" from "illegal" by
    substring-matching `Game_state.target_needed` in the error text.
    Rewording that constant silently turns every seven-zero 7 into an
    un-clickable card. It should be a variant, not a string.

11. **One limit, one constant.** Both branches independently added a
    10-player cap, and after the merge the two guards sat one after the other
    — the first one won and made the second's better error message dead code.
    Anything enforced in more than one place will diverge.

12. **A bot's event pipe has no reader.** Every broadcast writes to it, so it
    must be drained (`Pipe.drain`) or it grows for the lifetime of the room.
    Fine in a two-minute test, not in a long session.

---

## 14. Suggested next steps

- Add a test that parses `examples/*.rules` and diffs against the hand-coded
  rulesets — closes the §12 gap for ~10 lines.
- Add a smoke check on `page.ml`: extract the literal, assert no conflict
  markers, `node --check` the `<script>`, verify every `$('id')` resolves.
  (A throwaway version has been re-created by hand several times now — each
  time *after* it would have caught something. Worth 20 lines in `test/`.)
- Turn warning 9 back on for `bin/` (trap 9). The `lib/` cost may be real; the
  `bin/` cost is one afternoon and it closes the wire-protocol hole.
- Make `target_needed` a variant rather than a matched string (trap 10).
- Consider `current_color : Color.t option` (trap 6).
