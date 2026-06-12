#!/usr/bin/env bash
# Load the project-root CSV into raw.bitcoin_prices via psql \copy from stdin
# (no host mount, so it works the same on any Docker engine).
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

# Probe the header: confirm the layout and that Open Time is a datetime, not an epoch.
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

# Schemas and raw landing table (rough by design; real ingestion would own this),
# then load fresh. dbt creates the model schemas itself, but they are listed here
# so the load works against an empty database with no other setup.
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U "$user" -d "$db" -q <<'SQL'
create schema if not exists raw;
create schema if not exists staging;
create schema if not exists intermediate;
create schema if not exists marts;
create unlogged table if not exists raw.bitcoin_prices (
    open_time                     timestamp,
    open                          numeric,
    high                          numeric,
    low                           numeric,
    close                         numeric,
    volume                        numeric,
    close_time                    timestamp,
    quote_asset_volume            numeric,
    number_of_trades              integer,
    taker_buy_base_asset_volume   numeric,
    taker_buy_quote_asset_volume  numeric,
    ignore                        numeric
);
truncate raw.bitcoin_prices;
SQL

echo "loading raw.bitcoin_prices (streaming a 13GB file, this takes a few minutes)..."
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U "$user" -d "$db" \
    -c "\copy raw.bitcoin_prices from stdin with (format csv, header)" < "$csv"

count="$(docker compose exec -T db psql -tA -U "$user" -d "$db" \
    -c "select count(*) from raw.bitcoin_prices;")"
echo "loaded rows: $count"
