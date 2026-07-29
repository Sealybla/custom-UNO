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
- A file is a sequence of `rule` blocks; the next `rule` keyword ends the
  previous block, so no separators are needed.

## Conditions

| Text | `Rule.Condition.t` |
| --- | --- |
| `always` | `Always` |
| `your turn` | `IsPlayerTurn` |
| `card matches color` | `MatchesTopColor` |
| `card matches value` | `MatchesTopValue` |
| `card is wild` | `IsWildCard` |
| `card is skip` | `IsSkip` |
| `card is reverse` | `IsReverse` |
| `card is plus two` | `IsPlusTwo` |
| `card is plus four` | `IsPlusFour` |
| `pending draws > N` | `PendingDrawsGreaterThan N` |
| `continues stack` | `ContinuesStack` |
| `player draws` | `IsDrawAction` |
| `player passes` | `IsPassAction` |
| `<c> and <c>` / `<c> or <c>` / `not <c>` / `( <c> )` | `And` / `Or` / `Not` / grouping |

Precedence: `not` binds tightest, then `and`, then `or` (conventional).
Parentheses override.

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
| `draw until playable` | `DrawUntilPlayable` |
| `reverse direction` | `ReverseDirection` |
| `open stack` | `SetStackingValue` |
| `clear stack` | `ClearStackingValue` |
| `advance turn` | `AdvanceTurn` |
| `skip next player` | sugar for `AdvanceTurn; AdvanceTurn` |

Each effect becomes a `Mutate` in `Rule.t.actions`. `Sequence` and
`Chain_event` are not exposed in v1: the flat effect list already is a
sequence, and `Chain_event` needs concrete `Player.t`/`Card.t` values that
text can't name.

**Implicit `CheckWinner`:** the parser appends `Mutate CheckWinner`
immediately after every `play the card`. Forgetting it would mean wins
silently never register — too sharp a footgun to leave to users.

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

Shared special-card rules (`Ruleset.play_rules`):

```
rule "play wild" priority 100:
  when card is wild and your turn
  do play the card, set color to declared, advance turn

rule "play plus two" priority 100:
  when card is plus two and (card matches color or card matches value) and your turn
  do play the card, set color from card, add 2 pending draws, advance turn

rule "play skip" priority 100:
  when card is skip and (card matches color or card matches value) and your turn
  do play the card, set color from card, skip next player

rule "play reverse" priority 100:
  when card is reverse and (card matches color or card matches value) and your turn
  do play the card, set color from card, reverse direction, advance turn

rule "take penalty" priority 105:
  when pending draws > 0 and your turn and not (card is plus two or card is plus four)
  do apply pending draws, advance turn

rule "play plus four" priority 110:
  when card is plus four and your turn
  do play the card, set color to declared, add 4 pending draws, advance turn
```

Default variant adds:

```
rule "play matching card" priority 10:
  when (card matches color or card matches value) and your turn
  do play the card, set color from card, advance turn

rule "draw a card" priority 1:
  when player draws and your turn
  do draw 1 card, advance turn
```

Draw-until variant replaces "draw a card" with:

```
rule "draw until playable" priority 1:
  when player draws and your turn
  do draw until playable
```

Stacking variant replaces "play matching card" with:

```
rule "open stack" priority 10:
  when (card matches color or card matches value) and your turn
  do play the card, set color from card, open stack

rule "continue stack" priority 120:
  when continues stack and your turn
  do play the card, set color from card

rule "pass on stack" priority 120:
  when player passes and your turn
  do clear stack, advance turn
```

Every hand-coded rule is expressible, so the grammar covers the existing
engine. These texts become the round-trip test fixtures: parse them and
assert equality with the hand-coded `Rule.t` values.

## Decisions made (revisit if needed)

1. **`CheckWinner` is implicit** after `play the card` — never typed.
2. **`and` binds tighter than `or`**, parens to override.
3. **Priorities are raw ints** with a documented reference table (above).
   Named bands ("before defaults") can be sugar later.
4. **A ruleset file is complete** — it does not merge with defaults. Users
   start from a template containing the default rules and edit it. An
   `include defaults` directive can come later.
5. **v1 exposes no `Chain_event`/`Sequence`.**

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
successful updates broadcast `Rules_updated` to the room. The terminal
client submits with `rules <file>`.

The web UI (served at `http://localhost:<port+1>/`) is click-only
gameplay: clickable hand, draw pile, pass button, and a color picker for
wilds. The lobby's house-rules editor is the one typing surface — it
starts from the standard-rules template and submits to `/api/rules`,
rendering parse errors inline. Browsers reach the game through the HTTP
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
