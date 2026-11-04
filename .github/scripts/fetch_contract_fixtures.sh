#!/usr/bin/env bash
# Saves one fplAPI response per endpoint the app uses into FPLTests/Fixtures,
# where ContractTests decodes them with the app's models.
#
#   .github/scripts/fetch_contract_fixtures.sh [base URL]
#
# Run it to refresh the committed fixtures; the daily contract workflow runs it
# against production before the tests. Manager 1 is FPL's own public team.
set -euo pipefail

base="${1:-https://fpl-api-six.vercel.app/api}"
out="$(cd "$(dirname "$0")/../.." && pwd)/FPLTests/Fixtures"
manager=1
mkdir -p "$out"

fetch() {
  local name="$1" path="$2"
  curl --fail-with-body --silent --show-error --retry 2 --max-time 60 \
    "$base/$path" -o "$out/$name.json"
  echo "$name.json  <- /api/$path"
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
fetch picks "managers/$manager/picks"
