# Custom UNO

Multiplayer UNO where the players write the rules. An OCaml (Core/Async)
game server with a data-driven rule engine, a small text language for
house rules, and a click-based web UI.

## Run

```
dune build
dune exec custom-uno -- -port 8080
```

Open <http://localhost:8081/> — every browser tab is a player (2+ needed
to start). Optionally boot with a rule file:

```
dune exec custom-uno -- -port 8080 -rules examples/stacking.rules
```

## Play with friends on other devices

```
./scripts/share.sh
```

This starts a Cloudflare quick tunnel and prints a public
`https://….trycloudflare.com` link — anyone who opens it on any device
joins your game. The link is temporary: a new URL every run, gone when
the script stops. For a permanent URL you'd use a named Cloudflare
tunnel on your own domain (requires a Cloudflare account:
`cloudflared tunnel login`).

## Custom rules

Rules are edited in the lobby before a game starts: preset variants, a
build-a-rule form for newcomers, a click-to-insert cheat sheet, and live
validation while typing. The rule language and its architecture are
documented in [docs/rule-language.md](docs/rule-language.md).

## Development

```
dune runtest                                  # expect-test suite
dune exec uno-client -- -name alice -port 8080   # terminal client (testing)
```
