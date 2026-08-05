# How the engine picks between competing rules

Answering three questions precisely:

1. Which rules are compared against each other?
2. How does priority actually decide?
3. What happens when two rules contradict?

Source: `Rule_engine.process_event` in `lib/rule_engine.ml`.

---

## 1. The short answer

> Every rule whose **condition is true** for this exact (state, action) is a
> candidate. They are ranked by **priority descending, then by id ascending**,
> and **the single top-ranked candidate runs. Nothing else runs at all.**

There is no contradiction *resolution*, because there is never a second rule to
contradict with. Losing rules are not merged, not warned about, not partially
applied — they are simply not executed. "Contradiction" between two rules is
always settled by suppression.

---

## 2. The actual algorithm

The whole thing is about twenty lines:

```ocaml
let rec process_event rules state evt =
  (* 0. a finished game accepts nothing *)
  let%bind () =
    match state.winner with
    | Some w -> Or_error.error_s [%message "Game is over" ~winner:(w : int)]
    | None -> Ok ()
  in
  (* 1. rank ALL rules: priority descending, ties broken by id ascending *)
  let sorted_rules =
    List.sort rules ~compare:(fun r1 r2 ->
      match Int.compare r2.priority r1.priority with
      | 0 -> Int.compare r1.id r2.id
      | c -> c)
  in
  (* 2. keep only those whose condition holds right now *)
  let matching_rules =
    List.filter sorted_rules ~f:(fun rule -> eval_condition state evt rule.condition)
  in
  match matching_rules with
  | [] -> Or_error.error_string "Illegal move: no rule allows that right now"
  (* 3. run the first one. The tail is discarded, unexamined. *)
  | rule :: _ ->
    List.fold_result rule.actions ~init:state ~f:(fun curr_state eff ->
      Game_state.apply_effect
        ~card_playable:(ruleset_accepts_play rules)
        curr_state
        ~event:evt
        eff)
```

Four steps: **reject if the game is over → rank everything → filter to matches
→ run the head.** (It is `let rec` because `ruleset_accepts_play` — how the
draw effects judge the card they just drew — simulates a play back through
this same machinery, so "playable" always means what the rules in force say,
not official-rules matching.)

---

## 3. Which rules are compared?

**All of them are ranked; only the matching ones compete.**

The sort runs over the entire ruleset, but that is just ordering — it has no
effect on which rules are eligible. Eligibility is decided entirely by
`eval_condition state evt rule.condition`. A rule whose condition is false is
not "outranked"; it was never in the running.

So for a given click, the competition is exactly:

```
candidates = { rule ∈ ruleset | rule.condition is true for (this state, this event) }
winner     = the candidate with the highest priority
             (ties → lowest id)
```

Two consequences that surprise people:

**A rule can win an action it was never written for.** Conditions are
predicates over `(state, event)`, and several of them *ignore the event
entirely* — `Always`, `IsPlayerTurn`, `StackIsOpen`, `PendingDrawsGreaterThan`.
A rule reading `when your turn` is true for a card play, a draw, a pass, **and**
an UNO button press. It competes for all four.

This is exactly why the UNO rules sit at priorities 200/190/180: they must
outrank every ordinary rule, or a generous `when always` rule would swallow UNO
presses.

**"Highest priority" is global, not per-category.** There is no notion of "the
play rules" versus "the draw rules". One flat list, one comparison.

---

## 4. How ties are broken, and where ids come from

The comparator is explicit about ties rather than relying on sort stability:

```ocaml
match Int.compare r2.priority r1.priority with
| 0 -> Int.compare r1.id r2.id     (* lower id wins *)
| c -> c
```

For **parsed rules**, `Rule_parser` assigns ids sequentially in final source
order:

```ocaml
List.mapi merged ~f:(fun i (name, rule) -> name, { rule with Rule.id = i + 1 })
```

So for rules you write, the tie-break reads simply: **equal priority → the rule
defined first wins.**

One subtlety. `merged` is the list *after* same-name override, and override
replaces a rule **in place**:

```ocaml
if List.exists acc ~f:(fun (n, _) -> String.Caseless.equal n name)
then List.map acc ~f:(fun (n, r) -> if ... then n, rule else n, r)   (* in place *)
else acc @ [ name, rule ]                                            (* appended *)
```

So redefining a preset rule keeps the *original's* position, and therefore its
id and its tie-break standing. Redefining `"wild card"` at the bottom of your
file does not push it to the back of the queue.

For the **built-in rulesets**, ids are hand-written literals (`id = 1`,
`id = 30`, `id = 40`). I checked all four base variants: no ruleset contains a
duplicate id, so no tie is ever unresolved. But that is a hand-maintained
invariant with nothing enforcing it — see trap 3 in §9.

---

## 5. So what happens when two rules contradict?

It depends on *how* they collide. There are four distinct cases, and only one
of them is diagnosed for you.

### Case A — different priorities: the higher one wins, silently

```
rule "sevens swap hands" priority 60:
  when card is 7 and your turn
  do play the card, swap hands with chosen player, advance turn

rule "normal play" priority 10:
  when card matches color and your turn
  do play the card, set color from card, advance turn
```

Play a matching 7 and both conditions are true. Priority 60 beats 10, so the
swap happens and the ordinary play rule never runs — its `set color from card`
does not execute either. **The loser contributes nothing, not even the parts
that don't conflict.**

This is the single most common source of confusion: adding a rule does not *add*
behaviour, it *replaces* whatever it outranks for the cases both match.

### Case B — same priority, identical conditions: first defined wins, and the linter catches it

```
rule "a" priority 50: when card is red do play the card, advance turn
rule "b" priority 50: when card is red do reject "no red cards"
```

Same priority, so the lower id wins — `"a"`, defined first. `"b"` can **never**
fire under any circumstances.

This is the one contradiction the project detects, at authoring time, in
`dead_rule_warnings`:

```ocaml
if j <> i
   && Rule.Condition.equal other.condition rule.condition
   && (other.priority > rule.priority
       || (other.priority = rule.priority && j < i))
then Some other_name
```

You get a `Dead_rule` warning in the editor:

> rule "b" can never fire — rule "a" has the same condition and always wins
> (higher priority first; a tie goes to the rule defined first)

Note the strictness: it requires `Condition.equal` — **structurally identical**
conditions. `card is red` and `card is red and always` are logically equivalent
but not equal, so the second slips through undetected. The check is deliberately
conservative; it only reports what it is certain about, and offers no automatic
fix because which twin to change is a judgement call.

### Case C — same priority, *overlapping* conditions: first defined wins, and nothing warns you

```
rule "block action cards" priority 50: when card is action do reject "..."
rule "skips are special"  priority 50: when card is skip   do play the card, advance turn
```

These conditions are neither identical nor disjoint — a skip satisfies both. For
skips, the first-defined rule wins; for other action cards, only the first
applies; for number cards, neither.

**This is the dangerous case.** It is a genuine contradiction, it is decided by
declaration order, and no lint fires because the conditions aren't equal. If you
mean one to take precedence, say so with priorities instead of relying on
position.

### Case D — the winner can't actually perform its effects: the whole action fails

Winning is decided by **condition only**. The engine does not check that the
winner's effects make sense for this event. If they don't, `fold_result` returns
an error on the first failing effect:

```ocaml
List.fold_result rule.actions ~init:state ~f:(fun curr_state eff ->
  Game_state.apply_effect curr_state ~event:evt eff)
```

and — importantly — **there is no fallback to the runner-up.** The match arm is
`rule :: _`; the tail is discarded before any effect runs. The player's action
is rejected outright, and the state is left untouched (the fold threads a fresh
state and only commits on success).

So a badly-scoped high-priority rule doesn't just take over a move, it can make
that move *impossible* — and the error the player sees comes from the effect,
not from anything explaining which rule intercepted them.

This is also how the deliberate blocking idiom works. `Reject msg` is an
ordinary effect, so "no going out on an action card" is just a high-priority
rule whose effect list ends in a refusal.

---

## 6. What happens when *no* rule matches

```ocaml
| [] -> Or_error.error_string "Illegal move: no rule allows that right now"
```

Nothing is illegal by default *and* nothing is legal by default — legality is
entirely "some rule said yes". Delete every rule mentioning draws and drawing
becomes impossible, with no special-casing anywhere.

This is also why `Missing_play` exists as a lint: a rule that wins a card play
but omits `play the card` doesn't reject the click, it **accepts it and does
nothing else** — the card stays in your hand and the turn may not advance. That
looks like a frozen UI, not an error.

---

## 7. Inside the winning rule: effects are ordered and all-or-nothing

The winner's `actions` are a plain `Effect.t list`, applied left to right, each
against the state the previous one produced. `fold_result` short-circuits, so
the **first failing effect discards the whole action**.

Order therefore carries meaning. `play the card` expands to
`[PlayTriggeringCard; CheckWinner finish]`, so in seven-zero:

```
do play the card, set color from card, swap hands with chosen player, advance turn
```

the winner check runs *before* the hands move — going out on your last 7 wins
rather than handing your empty hand away. Swap those two effects and the rule
means something different.

---

## 8. A worked example

Ruleset: `use standard` plus jump-in. Alice is the current player. **Bob** — not
on turn — plays a card exactly matching the top card's colour and number.

Candidates, evaluated against `(state, CardPlayed {player = Bob; ...})`:

| rule | priority | condition | true? |
|---|---|---|---|
| uno call | 200 | `IsUnoCall and CallerHasUno and not SomeoneElseHasUno` | ✗ — not an UNO press |
| uno catch | 190 | `IsUnoCall and SomeoneElseHasUno` | ✗ |
| uno false-call | 180 | `IsUnoCall` | ✗ |
| **jump in** | **130** | `MatchesTopExactly and not IsActionCard and not IsPlayerTurn and not StackIsOpen` | **✓** |
| play +4 | 110 | `IsPlusFour and IsPlayerTurn` | ✗ — not Bob's turn |
| wild/skip/reverse/+2 | 100 | `... and IsPlayerTurn` | ✗ — not Bob's turn |
| generic play | 10 | `(MatchesTopColor or MatchesTopValue) and IsPlayerTurn` | ✗ — not Bob's turn |
| draw / pass-after-draw | 1 | `IsDrawAction` / … | ✗ |

One candidate, so it wins by default. Its effects run in order:

```
JumpToActor          -> turn moves to Bob
PlayTriggeringCard   -> the card goes down
CheckWinner First_out
SetColorFromTriggeringCard
AdvanceTurn          -> continues from Bob, so everyone between loses their go
```

Now remove the `not IsPlayerTurn` guard, so jump-in matches on-turn plays too.
When *Alice* plays an exactly-matching card, both jump-in (130) and generic play
(10) are candidates. Jump-in wins on priority, `JumpToActor` sets the turn to
Alice — who already had it — and the move quietly behaves differently from the
one you thought you were writing. Nothing errors; nothing warns. That is Case A
biting.

---

## 9. Traps

1. **A rule replaces, it does not add.** If your new rule outranks an existing
   one for some inputs, the old rule's effects are gone for those inputs —
   including the parts you wanted to keep. Copy them into your rule.

2. **Conditions that ignore the event compete for every action.** `Always`,
   `IsPlayerTurn`, `StackIsOpen`, `PendingDrawsGreaterThan`. A `when your turn`
   rule at priority 250 would win UNO presses too.

3. **Built-in ids are hand-assigned literals.** Every base variant is currently
   collision-free (verified), but two rules sharing a priority *and* an id would
   make the comparator return `0`, leaving their order unspecified. Parsed rules
   can't hit this — the parser numbers them — so it is a hazard only when
   hand-editing `Rule_engine.Ruleset`.

4. **The dead-rule lint only catches structurally identical conditions.**
   Overlapping-but-different conditions at equal priority (Case C) are silently
   resolved by declaration order.

5. **No fallback to the runner-up.** If the winner's effects fail, the action
   fails. The second-place rule is never consulted.

6. **Priorities are a total order over one flat list.** There are no
   per-category ladders; a number chosen for a draw rule competes with the play
   rules too.

---

## 10. Practical guidance

- **Decide precedence with priority, never with position.** Position only
  matters for exact ties, which means it usually matters by accident.
- **Leave gaps.** The built-ins use 1 / 10 / 60 / 100 / 105 / 110 / 120 / 130 /
  180–200 precisely so a new rule can be slotted between two existing ones
  without renumbering.
- **Make conditions narrow.** A rule that wins more actions than you intended is
  the failure mode, and it presents as "the button does nothing" rather than as
  an error.
- **Watch the editor warnings.** `Dead_rule` means a rule is unreachable;
  `Missing_play` / `Missing_advance` mean a rule wins the click and then strands
  the game.

### Reference: built-in priorities

| priority | rules |
|---|---|
| 200 / 190 / 180 | UNO: call / catch / false-call |
| 130 | jump in |
| 120 | continue stack, pass on stack |
| 110 | play +4 |
| 105 | take stacked penalty |
| 100 | wild, skip, reverse, +2 |
| 60 | seven-zero's 7 and 0 |
| 50 | parser default when `priority` is omitted |
| 10 | generic play / open stack |
| 1 | draw, pass-after-draw |

Note that **50 is the default**, sitting between generic play (10) and the
specials (100). A rule written with no priority already outranks ordinary card
play — which is usually what you want, and occasionally not.
