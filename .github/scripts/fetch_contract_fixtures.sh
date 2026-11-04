#!/usr/bin/env bash
# Saves one fplAPI response per endpoint the app uses into FPLTests/Fixtures,
# where ContractTests decodes them with the app's models.
#
#   .github/scripts/fetch_contract_fixtures.sh [base URL]
#
# Run it to refresh the committed fixtures; the daily contract workflow runs it
# against production before the tests. Manager 1 is FPL's own public team.
#
# A 503 that outlasts the retries (FPL down or updating), or the picks 404 before
# the season's first deadline, keeps the committed fixture with a warning instead
# of failing. Any other error fails.
set -euo pipefail

base="${1:-https://fpl-api-six.vercel.app/api}"
out="$(cd "$(dirname "$0")/../.." && pwd)/FPLTests/Fixtures"
manager=1
mkdir -p "$out"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

warn() {
  if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::warning::$1"; else echo "warning: $1" >&2; fi
}

# fetch NAME PATH [STATUS that keeps the committed fixture]
fetch() {
  local name="$1" path="$2" keep_on="${3:-}" status
  status=$(curl --silent --show-error --retry 4 --retry-delay 15 --max-time 60 \
    --write-out '%{http_code}' -o "$tmp" "$base/$path")
  if [ "$status" = 200 ]; then
    mv "$tmp" "$out/$name.json"
    echo "$name.json  <- /api/$path"
  elif [ "$status" = 503 ] || [ "$status" = "$keep_on" ]; then
    warn "/api/$path returned $status; kept the committed $name.json"
  else
    echo "/api/$path returned $status:" >&2
    cat "$tmp" >&2
    exit 1
  fi
}

fetch events events
# The live endpoint needs a gameweek; the current one (or the next, before the season) has data.
gameweek=$(jq -r '(map(select(.is_current)) + map(select(.is_next)) + [{id: 1}])[0].id' "$out/events.json")

fetch elements elements
fetch element elements/1
fetch elements-position elements/position/1
fetch teams teams
fetch fixtures "fixtures?started=false"
fetch live "events/$gameweek/live"
fetch manager "managers/$manager"
fetch transfers "managers/$manager/transfers"
fetch history "managers/$manager/history"
# No picks until the first deadline.
fetch picks "managers/$manager/picks" 404

# The manager's own names are personal; the team name is what the app and tests check.
jq -c '.player_first_name = "" | .player_last_name = "" | .player_region_name = null' \
  "$out/manager.json" > "$tmp" && mv "$tmp" "$out/manager.json"
