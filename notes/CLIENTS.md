# The two clients: `web.ml` and `client.ml`

How a player's click becomes a game action, by two different routes — and
whether the second route still earns its keep.

Companion to `ARCHITECTURE.md` §8. That file sketches the layering; this one
walks the functions.

---

## 1. The problem both files solve

`server.ml` speaks exactly one language: **Async RPC over TCP, with `bin_prot`
payloads**. That is a binary, typed, persistent-connection protocol.

A browser cannot speak it. Not "it would be awkward" — it structurally cannot:
no raw TCP, no `bin_prot` codec, no way to hold an Async pipe.

So there are two clients:

| | `bin/client.ml` | `bin/web.ml` + `bin/page.ml` |
|---|---|---|
| talks to the server via | Async RPC, directly | Async RPC, on the browser's behalf |
| talks to the user via | stdin / stdout | HTTP + JSON |
| is | a client | a **bridge**: RPC client on one side, HTTP server on the other |
| lines | ~214 | ~591 + ~2300 |

Both are built from `bin/dune` as `uno-client` and `custom-uno`.

---

## 2. `web.ml` — the bridge

### 2.1 The shape

The confusing thing about `web.ml` on first read is that it is **not the web
server**. `main.ml` owns the HTTP listener and routes `/api/*` into
`Web.handle`. `web.ml` is a translation layer with two faces:

```
browser ──HTTP/JSON──> web.ml ──Async RPC──> server.ml
        <──JSON queue──        <──event pipe──
```

Requests translate synchronously. Events cannot — the server pushes them down a
pipe whenever it likes, and HTTP has nobody to push to. So events are **queued
per player** and the browser drains the queue by polling.

### 2.2 `Session.t` — one RPC connection per browser player

```ocaml
type t =
  { conn : Rpc.Connection.t
  ; events : string Queue.t      (* JSON-encoded, in arrival order *)
  ; mutable last_poll : Time_ns.t
  }
```

Sessions are keyed `code ^ "/" ^ name` (`session_key`), because **names are
only unique within a room** — two rooms can each have an "alice".

The critical design decision is one RPC connection *per player*, not one shared
connection for the whole bridge. Everything below follows from it.

### 2.3 `join` — the function that matters most

Called from `/api/join`. The interesting path is `fresh_join`:

1. `connect t` — open an RPC connection to `127.0.0.1:rpc_port`
2. `join_lobby_rpc` — register the name in the room
3. `game_stream_rpc` — a **`Pipe_rpc`**, returning a `Pipe.Reader.t` of
   `Server_to_client.t`
4. install the pump:

```ocaml
don't_wait_for
  (Pipe.iter_without_pushback reader ~f:(fun event ->
     Queue.enqueue session.events (event_json event)))
```

That last step is the whole bridge in four lines: every event the server ever
sends this player is converted to JSON *on arrival* and parked in a queue. The
browser's next `/api/poll` takes whatever accumulated.

`iter_without_pushback` is deliberate — the bridge must never apply
backpressure to the game server. A browser that stops polling must not be able
to stall the room for everyone else. The cost is an unbounded queue, which is
bounded in practice by the reaper (§2.6).

`join` also handles the **page reload** case: if a live session already exists
for that `code/name`, it refreshes `last_poll` and returns `Ok` rather than
opening a second connection. Without this, hitting F5 would look to the server
like a *second* player with a duplicate name.

### 2.4 `with_session` — the guard on every action

```ocaml
let with_session t ~code ~name ~f =
  match Hashtbl.find t.sessions (session_key ~code ~name) with
  | None -> return (Or_error.error_string "Not in the room ... reload the page")
  | Some session ->
    session.last_poll <- Time_ns.now ();   (* <-- *)
    f session
```

Every gameplay route funnels through this: `take_action`, `start_game`,
`submit_rules`, `set_ready`, `set_bots`, `poll`, `get_state`.

Note the marked line. **Any** request refreshes liveness, not just polls — so a
player who is actively clicking never expires even if a poll response is lost.

### 2.5 `event_json` — the translation table

One exhaustive match from `Action.Server_to_client.t` to a JSON string, e.g.

```ocaml
| Jumped_in { player_name } ->
  sprintf {|{"type":"jumped_in","player":%s}|} (jstr player_name)
```

Every message carries a `"type"` tag, which is what `page.ml`'s reducer
switches on. The JSON is hand-rolled — `jstr` / `jlist` / `card_json` — so the
project takes no JSON dependency. `json_escape` handles quotes, backslashes,
control characters, and `\uXXXX` for anything below 0x20.

**This match is the wire contract.** Adding a *variant* to
`Server_to_client.t` breaks the build here, which is what you want. Adding a
*field* to an existing variant does not — see §5.

### 2.6 Liveness: polling *is* the heartbeat

This is the neatest idea in the file, and it is easy to miss.

```ocaml
Clock_ns.every (Time_ns.Span.of_sec 3.) (fun () ->
  Hashtbl.filter_inplace t.sessions ~f:(fun session ->
    let alive =
      (not (Rpc.Connection.is_closed session.conn))
      && Time_ns.Span.( < ) (Time_ns.diff now session.last_poll) session_expiry
    in
    if not alive then don't_wait_for (Rpc.Connection.close session.conn);
    alive))
```

The browser polls every **700 ms**; a session expires after **8 s** of silence
— roughly eleven missed polls, so a slow network doesn't evict a live player.

When a session expires the bridge **closes its RPC connection**. It does not
notify the game server, because it doesn't need to: `server.ml` already watches
`Rpc.Connection.close_finished` and converts a mid-game dropout into a bot.

That is the payoff for one-connection-per-player. Because a browser player owns
a real RPC connection, *browser presence and RPC presence are the same fact*,
and a tab closing gets exactly the same handling as a terminal client dying.
A shared connection would have forced a second, parallel presence mechanism —
and two mechanisms for one fact drift apart.

`/api/leave` is the fast path: `page.ml` fires a `navigator.sendBeacon` on
unload, and `leave` drops the session and closes the connection immediately,
instead of waiting out the 8 s timeout.

### 2.7 `poll` vs `get_state` — deltas vs snapshot

```ocaml
let poll      = (* drain the queue *)
let get_state = (* Queue.clear FIRST, then ask the server for a snapshot *)
```

`poll` is the steady-state loop: take the accumulated events, clear, return.

`get_state` (`/api/state`) asks the server for a *replayable* description of
the current situation via `get_state_rpc` — used on reconnect and reload.

The `Queue.clear` before the snapshot is a real bug fix, not tidiness. Queued
events describe changes that happened *before* the snapshot was taken. Applying
them on top of a fresh snapshot would replay history forwards over current
truth. Snapshot wins; the deltas it supersedes are dropped.

### 2.8 `rpc_result` — flattening two error layers

```ocaml
let rpc_result deferred =
  match%map deferred with
  | Error err | Ok (Error err) -> Error err
  | Ok (Ok ()) -> Ok ()
```

A dispatch can fail two ways: the *transport* failed (`Error err`), or the
transport succeeded and the *game* refused (`Ok (Error err)`). The browser
cannot act differently on those, so they collapse into one. The `Error err | Ok
(Error err)` or-pattern binding the same name is the idiomatic way to say it.

### 2.9 `handle` — the router

Dispatches on `Uri.path`. `with_ident` extracts and validates `?code=&name=`
(uppercasing the code) and 400s when either is missing.

Routes group into four families:

| family | routes | session needed |
|---|---|---|
| room lifecycle | `create-room`, `join`, `leave` | no / yes |
| lobby | `ready`, `bots`, `start`, `rules` | yes |
| gameplay | `play`, `draw`, `pass`, `uno` | yes |
| read | `poll`, `state` | yes |
| stateless helpers | `check-rules`, `preset-rules` | **no** |
| accounts | `login`, `me`, `mode-save`, `mode-delete` | no (token) |

`check-rules` is worth noting: it parses text and returns lint warnings with no
session and no room. That is what powers live feedback in the rules editor —
you get errors as you type, before you have committed anything to a game.

Accounts are optional. `login` returns a random 32-hex token held in an
in-memory `tokens` table; `with_token` resolves it. Tokens do **not** survive a
server restart — hence the error text *"or the server restarted"*. Account data
itself is persisted to a sexp file, and a corrupt file is fatal at boot rather
than silently overwritten.

---

## 3. `client.ml` — the terminal client

Much smaller, because it has no translation to do. Three functions.

### 3.1 `print_event`

An exhaustive match over `Server_to_client.t` that `print_s`-es each variant.
The structural twin of `event_json` — same input type, different output medium.

### 3.2 `handle_line`

Parses a stdin line and dispatches the matching RPC:

```
ready | unready | start | draw | pass | uno
play <card_id> [color] [swap target]
rules <file>
```

The `play` parser is the one piece of real logic:

```ocaml
| [ x ] ->
  (match Card.Color.of_string x with
   | Some c -> Some c, None      (* it's a color *)
   | None   -> None, Some x)     (* so it must be a player name *)
```

One optional argument, two possible meanings, disambiguated by *type* rather
than by position — a nice trick for a terminal UI, since `play 42 red` and
`play 42 bob` both read naturally.

`rules <file>` reads a local file and submits it, which is the quickest way to
try a ruleset without pasting it into a browser textarea.

### 3.3 `run`

```ocaml
don't_wait_for (Pipe.iter_without_pushback reader ~f:print_event);
Pipe.iter (Reader.lines (Lazy.force Reader.stdin)) ~f:(handle_line conn)
```

Two concurrent loops: events print as they arrive, commands are read from
stdin. Compare with `web.ml`, where the first loop enqueues instead of
printing, because there is no terminal to print to.

---

## 4. Is `client.ml` necessary?

**As a way to play the game: no.** The browser is strictly better — it renders
the table, animates plays, highlights legal cards, and edits rules. Nobody
should be asked to use the terminal client to play UNO. If it were deleted
tomorrow, no player would notice.

**As a development tool: it earns its keep, for one specific reason.**

Look at what the two paths traverse:

```
client.ml  →  RPC  →  server.ml  →  rule_engine
page.ml    →  HTTP →  web.ml  →  RPC  →  server.ml  →  rule_engine
                      ^^^^^^^^^^^^^^ extra layers, one of which the compiler
                                     does not check at all
```

`page.ml` is a single OCaml string literal. The compiler validates **none** of
it. `web.ml`'s JSON is hand-built with `sprintf`. So when the browser
misbehaves, "is the game logic wrong, or is the presentation wrong?" is a real
question with an expensive wrong answer.

`client.ml` answers it in one command. It touches the same server and the same
engine while bypassing JSON, HTTP, sessions, polling, and 2300 lines of
unchecked JavaScript. If the terminal client shows correct behaviour and the
browser doesn't, the bug is below `web.ml` — and you have halved the search
space without a debugger.

That is not hypothetical: a jump-in bug reported as "the engine rejects my
play" turned out to be the lobby never *submitting* the rules. A path that
skips the UI is exactly what distinguishes those two.

Two weaker arguments, for completeness:

- It is a second player you can drive from a shell script, which is how the
  multi-player probes in this project's scratch history worked.
- `print_event`, like `event_json`, is an exhaustive match — so a new protocol
  variant breaks two builds instead of one.

### The honest costs

- **Every protocol change touches it.** It conflicted in both the recent merge
  and the rebase. It is not free.
- **Nothing tests it.** `dune runtest` never runs it; it can only rot in ways
  the compiler happens to catch.
- **It duplicates rendering.** `print_event` and `event_json` are the same
  traversal written twice.

### Verdict

Keep it, but be clear about why: it is **a diagnostic instrument, not a
feature**. ~214 lines is a fair price for the ability to bisect the stack.

The one change worth making is to stop it rotting silently — a test that boots
a server, runs two terminal clients through a scripted game, and asserts on
their output would exercise `print_event`, `handle_line`, and the RPC surface
in one go. That would also make it a genuine integration test, which the
project currently has none of.

If instead you decide it isn't worth the maintenance, delete it outright rather
than leaving it half-maintained. A debugging tool you don't trust is worse than
no debugging tool, because you'll waste an afternoon doubting its output before
you doubt the code.

---

## 5. The trap both files share

`web.ml` and `client.ml` both **destructure** `Server_to_client.t` records:

```ocaml
| Lobby_updated { players; ready_players; bot_players; last_winner } -> ...
```

Warning 9 (missing record fields) is disabled in this project. So:

- adding a **variant** → both files fail to compile. Good.
- adding a **field** to an existing variant → both files compile silently and
  quietly ignore it. The browser simply never learns the new information.

This has bitten three times, most recently when `bot_players` was added to
`Lobby_updated`. The build was green; the field just never reached the page.

**After adding a field to anything on the wire, grep both consumers by hand.**
See `ARCHITECTURE.md` trap 9.
