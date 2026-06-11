#!/usr/bin/env bash
# Load the project-root Binance 1-second CSV into raw.bitcoin_prices.
# Streams the host file through psql's \copy from stdin via `docker compose
# exec -T`, so there is no host path mount and it behaves the same on Docker
# Desktop, Colima, and Rancher.
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$dir/.." && pwd)"
# shellcheck source=scripts/lib.sh
. "$dir/lib.sh"
cd "$root"

db="${POSTGRES_DB:-bitcoin}"
user="${POSTGRES_USER:-postgres}"

csv="$(find_dataset "$root")"
echo "dataset: $csv"

# Header probe: confirm the column layout, and that Open Time is a datetime
# string rather than a unix epoch, since the staging cast depends on it.
expected="Open Time,Open,High,Low,Close,Volume,Close Time,Quote Asset Volume,Number of Trades,Taker Buy Base Asset Volume,Taker Buy Quote Asset Volume,Ignore"
header="$(head -n 1 "$csv")"
if [ "$header" != "$expected" ]; then
    echo "error: unexpected CSV header." >&2
    echo "  expected: $expected" >&2
    echo "  found:    $header" >&2
    exit 1
fi
first_open_time="$(sed -n '2p' "$csv" | cut -d, -f1)"
if ! printf '%s' "$first_open_time" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}'; then
    echo "error: Open Time '$first_open_time' is not a 'YYYY-MM-DD HH:MM:SS' datetime." >&2
    echo "  the loader and staging cast assume datetime strings, not epochs." >&2
    exit 1
fi
echo "header ok; Open Time looks like a datetime ($first_open_time)"

wait_for_postgres

# Make sure the schemas and table exist even if the init mount did not run
# (e.g. a pre-existing volume), then load fresh.
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U "$user" -d "$db" -q < db/init/001_schemas.sql
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U "$user" -d "$db" -q \
    -c "truncate raw.bitcoin_prices;"

echo "loading raw.bitcoin_prices (streaming a 13GB file, this takes a few minutes)..."
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U "$user" -d "$db" \
    -c "\copy raw.bitcoin_prices from stdin with (format csv, header)" < "$csv"

count="$(docker compose exec -T db psql -tA -U "$user" -d "$db" \
    -c "select count(*) from raw.bitcoin_prices;")"
echo "loaded rows: $count"
