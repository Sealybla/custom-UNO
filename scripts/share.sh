#!/usr/bin/env bash
# Expose the Custom UNO web UI on a public https link via a Cloudflare
# quick tunnel, so players on other devices can join with one URL.
#
# Usage: ./scripts/share.sh [web-port]
#   web-port defaults to 8081 (the game server's port + 1)
set -euo pipefail
PORT="${1:-8081}"

command -v cloudflared >/dev/null || {
  echo "cloudflared is not installed." >&2
  echo "Install it: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/" >&2
  exit 1
}

if ! (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then
  echo "Nothing is listening on port $PORT." >&2
  echo "Start the game first:  dune exec custom-uno -- -port $((PORT - 1))" >&2
  exit 1
fi

echo ">>> Starting a Cloudflare quick tunnel for http://localhost:$PORT"
echo ">>> Share the https://....trycloudflare.com URL below with your players."
echo ">>> The link changes every run and dies with this process (Ctrl+C to stop)."
exec cloudflared tunnel --url "http://localhost:$PORT"
