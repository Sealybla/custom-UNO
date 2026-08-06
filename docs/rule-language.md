# Rule language design

The text format users type to define rules, and how it maps onto `Rule.t`.
Target: `Rule_parser.parse_ruleset : string -> Rule_engine.Ruleset.t Or_error.t`.

## Shape of a rule

```
rule "play plus two" priority 100:
  when card is plus two and (card matches color or card matches value) and your turn
  do play the card, set color from card, add 2 pending draws, advance turn
```

- `rule "<name>"` — name is for error messages and display; `id` is
  auto-assigned by the parser (users never see ids).
- `priority N` — optional; defaults to 50 (above generic play at 10, below
  the special-card rules at 100).
- `when <condition>` — boolean expression over the trigger event + game state.
- `do <effect>, <effect>, ...` — comma-separated effect list, applied in order.
- `#` starts a comment to end of line. Keywords are case-insensitive.
- A file is a sequence of `rule` blocks and `use` lines; the next `rule`
  keyword ends the previous block, so no separators are needed.

## Presets and `use`

`use <preset>` expands, in place, to the full rule text of a built-in
ruleset (canonical texts in `lib/presets.ml`), so a variant can start from
a preset without retyping it:

```
use stacking

# same name as the preset's rule, so this redefines it: a reverse now
# also burns the next player for one card
rule "play reverse" priority 100:
  when card is reverse and (card matches color or card matches value) and your turn and not stack is open
  do play the card, set color from card, reverse direction, next player draws 1 cards, advance turn
```

The presets are `standard`, `stacking`, `draw until playable`, and the
combination `stacking with draw until playable` (stacking play rules with
draw-until drawing). The lobby's preset toggles emit exactly these lines.

Rule names are identities: a later rule with the same name as an earlier
one (case-insensitive) **replaces** it in place. That is how an extension
tweaks a preset rule — redefine it under the same name — and why `use`
never duplicates anything. Ids are assigned after this merge.

Subtraction works the same way: `remove rule "play plus four"` drops the
named rule from everything defined **above** it, so it belongs after the
`use` line it edits (removing a name nothing defined is an error that
lists what exists). The cards that rule powered simply become unplayable —
no rule accepts them. Removal is positional like redefinition: a later
rule with the same name re-adds it.

```
use standard
remove rule "play plus four"   # +4s are dead cards now
```

## Choosing between rules that clash

Only one rule fires per move — the highest priority, and among equals the
one written first. When two rules want the same move, that second half is
an accident of typing order rather than a decision, so the editor says so
and you answer with a `prefer` line:

```
prefer "sevens swap hands" over "play matching card"
```

It means exactly what it says: whenever both rules match, the named winner
takes the move. Unlike a hand-picked priority number, it records *that a
choice was made* and survives someone later renumbering things. Position
does not matter — a `prefer` line may name a rule defined further down.

Naming a rule that does not exist is an error listing the ones that do, and
so is a set of preferences that contradicts itself (`prefer "a" over "b"`
together with `prefer "b" over "a"`).

The editor flags three things worth answering:

- **can never fire** — every move this rule wants is already taken by a rule
  above it. Usually a narrow rule left *below* the broad rule it was meant
  to override; `prefer` fixes it.
- **impossible condition** — no situation could ever satisfy it, like
  `card is red and card is blue`.
- **two rules could both take this move** — same priority, overlapping
  conditions. Pick a winner.

A narrow rule sitting *above* a broad one is the opposite of a problem —
it is how `play skip` refines `play matching card` — so it is listed as
structure rather than flagged.

## Conditions

| Text | `Rule.Condition.t` |
| --- | --- |
| `always` | `Always` |
| `your turn` | `IsPlayerTurn` |
| `card matches color` | `MatchesTopColor` |
| `card matches value` | `MatchesTopValue` |
| `card matches exactly` | `MatchesTopExactly` (same printed colour *and* number; wilds never match) |
| `card is wild` | `IsWildCard` |
| `card is skip` | `IsSkip` |
| `card is reverse` | `IsReverse` |
| `card is plus two` | `IsPlusTwo` |
| `card is plus four` | `IsPlusFour` |
| `card is N` (0–9, e.g. `card is 7`) | `IsNumber N` |
| `card is red` (etc.) | `IsCardColor Red` |
| `card is action` | `IsActionCard` (skip, reverse, +2, +4 or wild) |
| `card is number` | `IsNumberCard` (any 0–9, whatever its color) |
| `active color is red` (etc.) | `ActiveColorIs Red` |
| `pending draws > N` | `PendingDrawsGreaterThan N` |
| `hand size > N` / `hand size = N` | `HandSizeGreaterThan N` / `HandSizeEquals N` — the acting player's hand, counted before a played card leaves it |
| `any opponent has N cards` / `any opponent has more than N cards` | `AnyOpponentHandEquals N` / `AnyOpponentHandGreaterThan N` — some player *other than the actor*; leader-watch and defense rules. Not to be confused with `someone has uno`, which is window-based (true only while another player is actually catchable), not a hand-size test |
| `top card is N` (0–9) / `top card is action` | `TopCardIsNumber N` / `TopCardIsAction` — what's *showing on the pile*, testable on any action (unlike `card is …`, which tests the played card) |
| `direction is clockwise` / `direction is counter` | `DirectionIsClockwise` (counter parses as its negation) |
| `draw pile is empty` / `draw pile < N` | `DrawPileLessThan 1` / `DrawPileLessThan N` — endgame triggers; the pile still reshuffles automatically |
| `continues stack` | `ContinuesStack` |
| `stack is open` | `StackIsOpen` |
| `drew playable card` | `DrewPlayableCard` |
| `player draws` | `IsDrawAction` |
| `player passes` | `IsPassAction` |
| `player calls uno` | `IsUnoCall` |
| `has uno` | `CallerHasUno` (the presser holds exactly one card) |
| `someone has uno` | `SomeoneElseHasUno` (another player is catchable) |
| `<c> and <c>` / `<c> or <c>` / `not <c>` / `( <c> )` | `And` / `Or` / `Not` / grouping |

Precedence: `not` binds tightest, then `and`, then `or` (conventional).
Parentheses override.

`card is 7` tests only the card's printed number — it says nothing about
whether the card matches the pile. A rule that should follow normal
matching wants `when card is 7 and (card matches color or card matches
value) and your turn`, the same shape as the built-in skip/reverse rules;
leave the matching clause out to make that number playable on anything.

Likewise `card is blue` tests the card's *printed* color (wilds have none,
so they never match), while `active color is blue` tests the table's
current color to match — whatever the last rule set it to. "Blue cards are
always playable" wants the first; "while blue is active, draws are
doubled" wants the second.

## Effects

| Text | `Game_state.Effect.t` |
| --- | --- |
| `play the card` | `PlayTriggeringCard` (+ auto `CheckWinner`, see below) |
| `set color from card` | `SetColorFromTriggeringCard` |
| `set color to declared` | `SetDeclaredColor` |
| `set color to red` (etc.) | `SetActiveColor Red` |
| `add N pending draws` | `AddPendingDraws N` |
| `apply pending draws` | `ApplyPendingDraws` |
| `draw N` / `draw N cards` | `ExecuteDraw N` |
| `next player draws N cards` | `DrawForNextPlayer N` (turn unchanged) |
| `draw until playable` | `DrawUntilPlayable` (draw 1, turn stays; a playable draw sets the drew-playable flag) |
| `draw and decide` | `DrawAndDecide` (draw 1; playable → keep turn + set flag, else advance) |
| `reverse direction` | `ReverseDirection` (with 2 players also skips the opponent, per official Uno) |
| `open stack` | `SetStackingValue` |
| `close stack` (or `clear stack`) | `ClearStackingValue` |
| `advance turn` | `AdvanceTurn` |
| `jump in` | `JumpToActor` (the turn moves to whoever played) |
| `skip next player` | sugar for `AdvanceTurn; AdvanceTurn` |
| `mark uno called` | `MarkUnoCalled` (shuts the presser's own catch window) |
| `penalize caller N cards` | `PenalizeUnoCaller N` |
| `penalize uncalled player N cards` | `PenalizeUnoTarget N` |
| `swap hands with next player` | `SwapHandsWithNext` (entire hands trade, in play direction) |
| `swap hands with chosen player` | `SwapHandsWithChosen` (the actor names the target; the web UI shows a player picker) |
| `rotate hands` | `RotateHands` (every hand moves one seat in play direction) |
| `everyone else draws N cards` | `AllOthersDraw N` |
| `chosen player draws N cards` | `ChosenPlayerDraws N` — the actor aims the card at any player (same picker as chosen swaps); unlike swaps, a winning final card still delivers its draws, matching the official +2/+4 |
| `reject "message"` | `Reject` — fail the whole action: the move becomes illegal and the clicker sees the message |

`Rule.t.actions` is a plain `Game_state.Effect.t list`, applied in order;
the first failing effect rejects the whole action and the state never
changes.

**Implicit `CheckWinner`:** the parser appends `CheckWinner`
immediately after every `play the card`. Forgetting it would mean wins
silently never register — too sharp a footgun to leave to users.

## When the game ends (`play until`)

By default the first player to empty their hand ends the game — everyone else
just loses. A `play until` line changes that, so play carries on for second
place, third place, and so on:

```
use standard
play until one player is left      # keep going until only one player has cards
```

Three forms:

| Text | Meaning |
| --- | --- |
| `play until first player finishes` | classic Uno; the default if the line is absent |
| `play until N players finish` | stop once N players are out |
| `play until one player is left` | everyone but the last player finishes |

A player who empties their hand is **out**: they keep their seat but are
skipped for the rest of the game. `Game_over` then carries the full finishing
order, so the results screen can show a podium rather than a single name.

Notes:

- The line is a **ruleset-wide setting, not a rule** — it takes no `when`/`do`
  and may appear anywhere in the file, including before or after `use`. Giving
  it twice is an error.
- `N` is clamped to one less than the number of players, since nobody can take
  the last place from themselves. `play until 5 players finish` at a table of
  three ends after two are out, rather than never ending.
- It applies to the whole ruleset: every `play the card` compiles to a
  `CheckWinner` carrying this mode, so preset rules pulled in by `use` obey it
  too.

## Playing out of turn (jump-in)

Nothing in the engine checks whose turn it is — that gate is the `your turn`
condition, which every ordinary play rule happens to carry. **Leave it out and
the rule fires whenever its other conditions hold, no matter whose turn it
is.** That is all "jumping in" is:

```
rule "jump in" priority 130:
  when card matches exactly and not card is action and not your turn and not stack is open
  do jump in, play the card, set color from card, advance turn
```

`jump in` moves the turn to whoever played, and the `advance turn` after it
carries on from there — so everyone sitting between the player whose turn it
was and the one who jumped loses their go. With seats `A B C D`, the turn on
`B`, and `D` jumping in, `B` and `C` are skipped and play resumes at `A`.

**The condition is yours to pick.** `card matches exactly` (same colour *and*
number as the top card) is only the default that ships with the `jump in`
preset. Anything the language can express works:

```
when card is plus two and not your turn              # jump in with any +2
when card matches value and not your turn            # looser: number only
when card matches exactly and not your turn and pending draws > 0
```

Notes:

- **Wilds never match `card matches exactly`.** They have no printed colour,
  so a wild-on-wild jump would set the active colour to `NoColor`, which makes
  every card playable. If you want wild jumps, write `when card is wild and
  not your turn` and pair it with `set color to declared`.
- **Keep `not stack is open`** in stacking rulesets, or a jump-in can barge
  into someone's open stack and strand it.
- **The default excludes action cards** (`not card is action`): the rule's
  effect list is the generic play sequence, so a jumped Skip would not skip
  and a jumped +2 would deliver no draws — in stacking rulesets it would
  even leave the original pending penalty to whoever holds the turn *after*
  the jump. To allow an action-card jump, write a rule that spells the
  effects out, e.g. `when card is plus two and not your turn do jump in,
  play the card, set color from card, next player draws 2 cards, advance
  turn, advance turn`.
- The UI highlights whatever the engine would accept (it asks the server
  rather than guessing), so a custom jump condition lights up correctly
  without any client change.

## Seven-zero (hands that move)

The classic 7-0 house rule ships as an **add-on preset**: unlike the base
presets it is not a complete ruleset, just two rules you `use` *after* a
base (the lobby's "7-0" toggle writes exactly this):

```
use standard
use seven zero
```

which expands to

```
rule "sevens swap hands" priority 60:
  when card is 7 and (card matches color or card matches value) and your turn and not stack is open
  do play the card, set color from card, swap hands with chosen player, advance turn

rule "zeros rotate hands" priority 60:
  when card is 0 and (card matches color or card matches value) and your turn and not stack is open
  do play the card, set color from card, rotate hands, advance turn
```

Notes:

- **The 7 swaps with a player of your choice** — the web UI pops a player
  picker when you click the 7 (the server marks such cards in
  `Hand_updated.swap_target_ids`, found by simulating the play and hitting
  the needs-a-target rejection). Prefer no questions? Redefine the rule
  with `swap hands with next player`. Bots pick the smallest hand.
- **Going out on a 7 or 0 wins.** The winner check runs the moment the
  card is played, before any hands move — same as real seven-zero — and a
  winning 7 never asks for a target.
- **Rotation respects play direction**: `rotate hands` passes every hand
  one seat along; after a reverse it flows the other way (same for
  `swap hands with next player`).
- Priority 60 beats the generic play rule (10) but loses to the specials
  (100+). In stacking rulesets a 7 or 0 that would have *opened* a stack
  swaps/rotates instead; mid-stack both rules are blocked (`not stack is
  open`) — without that guard a 7 played into an open stack would swap and
  walk away, stranding the stack on the next player.
- The UNO catch window follows the swap: swap yourself *into* a one-card
  hand and you are catchable until you call UNO, exactly as if you had
  played down to one.
- These rules override like any other: redefine `"sevens swap hands"` by
  name to change what a 7 does (e.g. `everyone else draws 2 cards` for a
  crueler table).

## Blocking plays (reject)

`reject "message"` fails the whole action: any effects before it are
discarded, the move is illegal, and the player who clicked sees the
message. The playability simulation sees the same error, so blocked cards
don't even light up in the hand. A blocking rule only needs to OUTRANK
whatever rule would have accepted the play:

```
rule "no action finish" priority 200:
  when card is action and hand size = 1
  do reject "you cannot go out on an action card"
```

`hand size = 1` counts the acting player's hand before the card leaves
it, so this fires exactly when an action card would have been the last
card. Leaving `your turn` out of the condition means it also blocks
out-of-turn jump-ins — usually what a table constraint wants, which is
why the checker doesn't nag reject-rules about the missing guard (or
about the missing `play the card`; not playing is the point).

## Settings

Directives configure the game the rules run in; they can sit anywhere in
the text alongside `use` and `rule` lines:

| Text | Effect |
| --- | --- |
| `deal N cards` | each player starts with N cards (default 7, N from 1 to 30) |
| `turn timer N seconds` | seconds before the server plays for a stalled player (default 20, N from 5 to 300) |
| `turn timer off` | no clock: turns wait forever |

Like same-named rules, a later settings line replaces an earlier one, and
submitting text with no such line returns the room to the default.
Starting a game checks the deck can cover the table: every hand plus the
flipped top card must fit in 108. Settings compose into whole game feels
a saved mode can capture:

```
# Speed UNO
use standard
use seven zero
deal 5 cards
turn timer 10 seconds
```

## The UNO button

Pressing UNO is its own action, separate from playing/drawing/passing. It
never consumes a turn and anyone may press at any time. While a catch
window is open the server flags it on every `Turn_changed`
(`uno_race`), and the web UI flashes **everyone's** UNO button — the
holder races to save themselves, everyone else races to catch them; the
flashing stops for the whole table the moment the press (or any other
action) settles it. The three UNO rules are resolved purely by priority:

```
rule "call uno" priority 200:
  when player calls uno and has uno and not someone has uno
  do mark uno called

rule "catch uno" priority 190:
  when player calls uno and someone has uno
  do penalize uncalled player 2 cards

rule "false uno call" priority 180:
  when player calls uno
  do penalize caller 2 cards
```

Read top to bottom, that says: while somebody is catchable, any press is a
catch (the `not someone has uno` guard keeps the self-claim rule out of the
way, so even a player who is themselves down to one card can make the
catch — only one window can be open at a time, so the guard never blocks a
genuine self-claim); otherwise a one-card press claims your own UNO, and a
press with nothing behind it costs the presser. The last rule matches *any*
press, so a press is always resolved by these rules and never falls through
to a turn rule — keep these priorities above everything else, because
conditions like `pending draws > N` and `your turn` do not look at what the
player actually did and would otherwise match a press.

**Who is catchable.** A player becomes catchable the moment they play down
to one card, and stops being catchable as soon as *another* player takes a
gameplay turn. Only one player can be catchable at a time, since only the
acting player's hand can shrink on their own move. This window is tracked by
`Game_state.update_uno_window` and is deliberately *not* an effect — rules
can spend the window but cannot redefine it.

`has uno` means "holds exactly one card", not "is catchable". A player whose
window has already closed can still press the button harmlessly rather than
being fined for it.

## EBNF

```
ruleset   ::= rule*
rule      ::= "rule" STRING [ "priority" INT ] ":"
              "when" cond
              "do" effect { "," effect }
cond      ::= or_cond
or_cond   ::= and_cond { "or" and_cond }
and_cond  ::= not_cond { "and" not_cond }
not_cond  ::= "not" not_cond | "(" cond ")" | atom
atom      ::= multi-word keyword phrase from the conditions table
effect    ::= multi-word keyword phrase from the effects table
```

Tokenizer splits on whitespace/punctuation; the parser matches multi-word
phrases by peeking ahead (e.g. `card` `is` `plus` `two` is one atom).

## Validation: the current rulesets, rewritten

Shared special-card rules (`Ruleset.base_special_rules`; wild is always
playable, skip/reverse must match like any other card):

```
rule "play wild" priority 100:
  when card is wild and your turn
  do play the card, set color to declared, advance turn

rule "play skip" priority 100:
  when card is skip and (card matches color or card matches value) and your turn
  do play the card, set color from card, skip next player

rule "play reverse" priority 100:
  when card is reverse and (card matches color or card matches value) and your turn
  do play the card, set color from card, reverse direction, advance turn
```

The +2/+4 rules differ per variant. Standard (and draw-until) use the
immediate form (`Ruleset.immediate_draw_rules`) — the victim draws on the
spot and is skipped:

```
rule "play plus two" priority 100:
  when card is plus two and (card matches color or card matches value) and your turn
  do play the card, set color from card, next player draws 2 cards, skip next player

rule "play plus four" priority 110:
  when card is plus four and your turn
  do play the card, set color to declared, next player draws 4 cards, skip next player
```

The stacking variant uses the deferred form
(`Ruleset.deferred_draw_rules`) — a pending counter the victim can stack
onto, with the penalty rule outranking everything except another +2/+4.
Its specials (and the +2/+4 rules) all carry `and not stack is open`
(`Ruleset.stacking_special_rules`): while a same-value stack is open, only
continuations or a pass are legal, so a same-color card can't sneak in
mid-stack:

```
rule "play plus two" priority 100:
  when card is plus two and (card matches color or card matches value) and your turn and not stack is open
  do play the card, set color from card, add 2 pending draws, advance turn

rule "play plus four" priority 110:
  when card is plus four and your turn and not stack is open
  do play the card, set color to declared, add 4 pending draws, advance turn

rule "take penalty" priority 105:
  when pending draws > 0 and your turn and not (card is plus two or card is plus four)
  do apply pending draws, advance turn
```

The standard and stacking variants handle drawing the same way — one
card, and a playable draw keeps the turn open so the player can play it
or pass via the "Done" button (this is the only time a bare pass is
legal outside the stacking rules):

```
rule "draw a card" priority 1:
  when player draws and your turn and not stack is open and not drew playable card
  do draw and decide

rule "pass after draw" priority 1:
  when player passes and your turn and drew playable card
  do advance turn
```

Default variant adds:

```
rule "play matching card" priority 10:
  when (card matches color or card matches value) and your turn
  do play the card, set color from card, advance turn
```

Draw-until variant replaces "draw a card" with the rule below and has
no pass rule at all, so the Done button never appears. Each draw click
takes one card and never ends the turn: a drawn playable card may be
kept and the drawing continued — the only way to end the turn is to
actually play a card:

```
rule "draw until playable" priority 1:
  when player draws and your turn
  do draw until playable
```

(`draw until playable` rather than `draw 1 cards`: on a dry deck the
former passes the turn, while a plain draw would be an accepted no-op
that leaves the seat with no way out.)

Stacking variant replaces "play matching card" with:

```
rule "open stack" priority 10:
  when (card matches color or card matches value) and your turn and not stack is open
  do play the card, set color from card, open stack

rule "continue stack" priority 120:
  when continues stack and your turn
  do play the card, set color from card

rule "pass on stack" priority 120:
  when player passes and your turn and stack is open
  do close stack, advance turn
```

The stack lifecycle: `open stack` records the played card's value and the
rule deliberately omits `advance turn`, so the player stays on turn and may
keep playing cards of that value (`continues stack`). `close stack` forgets
the recorded value — clicking Done fires it and ends the turn. While the
stack is open (`stack is open`), every other rule is guarded off, which is
why the specials above all carry `not stack is open`. (`clear stack` is an
accepted synonym for `close stack`.)

The combined variant (`use stacking with draw until playable`) is the
stacking rules with the draw rule swapped for draw-until drawing, guarded
so nobody draws mid-stack:

```
rule "draw until playable" priority 1:
  when player draws and your turn and not stack is open
  do draw until playable
```

Every hand-coded rule is expressible, so the grammar covers the existing
engine. These texts become the round-trip test fixtures: parse them and
assert equality with the hand-coded `Rule.t` values.

## Overriding a built-in rule

The engine runs exactly ONE rule per click — the highest-priority match —
so a custom rule never layers onto normal play; it competes with it.

**Tie-breaking is explicit**: when several matching rules share the top
priority, the one defined earliest in the ruleset text wins (the engine
sorts by priority, then by the parser-assigned id, which follows
definition order — see `Rule_engine.process_event`; a test pins this).
Since `use <preset>` expands at the top of the text, a custom rule at the
same priority as a built-in loses the tie and silently never fires — the
checker flags the identical-condition case as a dead rule. To beat a
built-in, either replace it by name or outrank it.

The way to change how a card behaves is to redefine the preset's rule under
its own name (rules merge by name, later definition wins) with the full
effect list:

```
use standard

rule "play reverse" priority 100:
  when card is reverse and (card matches color or card matches value) and your turn
  do play the card, set color to red, reverse direction, advance turn
```

The lobby editor's "Change a built-in rule" panel copies any preset rule's
text into the editor for tweaking. The checker
(`Rule_parser.parse_ruleset_checked`, surfaced by `/api/check-rules`)
warns about the easy mistakes, each with a one-click fix in the editor:

- a card-play rule without `play the card` — the card would stay in the
  hand;
- one that plays the card but lacks `advance turn` — the turn would never
  end (mid-stack rules are exempt: keeping the turn is the point);
- one that plays the card but has no color effect — the color to match
  would go stale (a blue 0 played on red keeps red active). Exempt when
  the condition guarantees a color match on every path (e.g. plain
  `card matches color`); rules on wilds are steered to
  `set color to declared` since a wild has no printed color;
- one without a `your turn` condition (see below).

## Turn order is just a condition

Nothing in the engine enforces turn order. The server accepts actions from
every player at any time; a rule fires for the *acting* player, and the
only thing keeping play orderly is that every normal rule requires
`your turn` — "the player doing this action is the player whose turn it
is". Omit it from a custom rule and that rule fires for anyone, even out
of turn (the checker warns; the composer pre-adds the line and shows a
hint when it's removed). The jump-in presets are exactly this, on purpose
— see "Playing out of turn" above. The checker therefore skips the
warning for two deliberate shapes: rules that say `not your turn`
explicitly (jump-in style), and rules that can only fire on the UNO
button, which is never turn-gated.

## Decisions made (revisit if needed)

1. **`CheckWinner` is implicit** after `play the card` — never typed.
2. **`and` binds tighter than `or`**, parens to override.
3. **Priorities are raw ints** with a documented reference table (above).
   Named bands ("before defaults") can be sugar later.
4. **A ruleset file is complete** — it does not merge with defaults. Users
   start from a template containing the default rules and edit it. An
   `include defaults` directive can come later.
5. **Actions are a flat effect list.** An earlier draft reserved
   `Chain_event`/`Sequence` AST nodes for rules that trigger other rules;
   they were never constructed and have been removed. Reintroduce
   deliberately if that power is ever wanted.

## Parser implementation plan

- `lib/rule_parser.mli`:
  ```ocaml
  val parse_ruleset : string -> Rule.t List.t Or_error.t
  ```
  (the result type equals `Rule_engine.Ruleset.t`, so it passes straight to
  `Rule_engine.apply_action` / `Server.start ~ruleset`)
- Hand-written: tokenizer (lowercase words, ints, strings, `:` `,` `(` `)`
  `>`) + recursive descent following the EBNF. No new dependencies.
- Errors are `Or_error` with line numbers, the offending token, and the
  enclosing rule's name: `(in rule "confused") (unknown condition (line 2
  at 'card'))` — these go straight back to the user who typed the rule.

**Status: implemented** in `lib/rule_parser.ml`. The three hand-coded
rulesets round-trip exactly (see the fixtures in
`test/test_custom_uno.ml`); the hand-coded rules' `CheckWinner` was moved
to sit immediately after `PlayTriggeringCard` to match the parser's
desugaring (semantically identical).

The server binary takes `-rules <file>` (e.g.
`custom-uno -port 8080 -rules examples/stacking.rules`); a bad or missing
file is a fatal boot error. `examples/standard.rules` is the template
users start a variant from; `examples/stacking.rules` is the stacking
variant.

The server hosts many isolated rooms, each identified by a 4-letter code
(`create_room_rpc` returns one; `join_lobby_rpc` takes code + name).
Every room has its own lobby, game, engine loop, and ruleset — the
`-rules` boot flag sets the default ruleset new rooms start from.

`submit_rules_rpc : string -> unit Or_error.t` lets any room member
replace that room's ruleset before a game starts (rejected mid-game);
parse errors come back over the wire for the rule editor to render, and
successful updates broadcast `Rules_updated` — carrying the accepted text
— so every member's editor syncs to the same rules (late joiners get the
text in their state snapshot, marked with an empty player name). The
terminal client submits with `rules <file>`.

Players can optionally log in on the join screen (`/api/login`; unknown
usernames are signed up on the spot) to keep a personal library of saved
rule "modes" — named snapshots of the rules editor's text. Logged-in
players get a "My modes" row in the lobby: click a mode to load it into
the editor (then submit as usual), save the current text under a name, or
delete one. Accounts and modes persist in a sexp file (`-users` flag,
default `uno-users.sexp`) handled entirely by the web bridge in
`bin/web.ml` + `lib/accounts.ml`; passwords are salted-MD5 (a speed bump
appropriate for a card game, not real security), and login tokens are
in-memory only — a server restart just means logging in again.

The lobby has a ready gate: `set_ready_rpc : bool -> unit Or_error.t`
toggles the caller's flag, `Lobby_updated` carries `ready_players` (and
`last_winner`, shown as a crown over that player in the lobby), and
`start_game_rpc` refuses until every member is ready, naming who is still
missing. Ready flags clear when a game starts, so rematches need a fresh
round of readying; leaving the lobby clears yours. The web lobby shows a
ready toggle, per-player ready tags, and a start button that stays
disabled until everyone is in; the terminal client uses `ready` /
`unready`.

The web UI (served at `http://localhost:<port+1>/`) is click-only
gameplay: clickable hand, draw pile, pass button, and a color picker for
wilds. On your turn every playable card lifts with a glow; cards that
could be chained as a same-value stack pulse gold (the server tells the
page whether the ruleset can open stacks via `stacking_enabled` on
`Game_started`). The pass button only appears when a pass is actually
legal: `Turn_changed` carries `can_pass` (the server dry-runs the rule
conditions against a Pass) and `stack_value` (the open stack's value, if
any). The top discard always wears the active color: when a wild's
declaration or a recoloring rule moves the color away from the card's
printed one, the card face itself is repainted (plus a pop animation on
the pile), not just the glow ring around it. A "Leave game" button (and the tab-close beacon) hands the seat to
a bot mid-game — bots continue stacks, stack +2/+4s onto pending
penalties, and pass when a stack runs dry; when the last human leaves,
the game is abandoned and the room closes. The lobby's house-rules editor
is the one typing surface — it
starts from the standard-rules template and submits to `/api/rules`,
rendering parse errors inline. Two click-only helpers feed it: "Change a
built-in rule" copies a preset rule's text in for tweaking, and the
composer ("Compose a new rule without typing") builds a brand-new rule
from chips — any number of and-joined conditions, each optionally negated,
plus ordered effects — showing a live preview of the rule text as it
grows. Picking a card-play condition pre-adds the standard play effects
(`play the card`, `set color from card`, `advance turn` — no advance for
`continues stack`) as removable chips, so composed card rules handle the
whole play by default; later effects slot in before the trailing turn
ender, and adding a second turn ender replaces the first. Browsers reach the game through the HTTP
→ RPC bridge in `bin/web.ml` (per-player RPC connection + polled JSON
event queue). Illegal actions come back to the acting player as an
`Action_rejected` event and show as a toast.

A page reload rejoins automatically (the tab remembers its player name)
and restores the table via `get_state_rpc`, which returns a snapshot of
the current lobby/game as a replayable event list. The server broadcasts
`Hand_counts` after every action, shown as count badges on the player
chips (a red "UNO!" badge at one card).

The rules editor is beginner-friendly: preset buttons load the Standard
/ Stacking / Draw-until-playable templates; a "build a rule without
typing" form (dropdown condition + effect chips + priority) generates
rule text into the editor; a cheat sheet lists every condition/effect
phrase with click-to-insert; and the editor live-validates as you type
via `POST /api/check-rules` (parse-only dry run, no session needed).
