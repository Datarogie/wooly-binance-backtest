#!/usr/bin/env bash
# Start db, load data, build dbt project, print answers. Re-runnable; skips load if data exists.
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$dir/scripts/lib.sh"
cd "$dir"

export DBT_PROFILES_DIR="$dir"
db="${POSTGRES_DB:-bitcoin}"
user="${POSTGRES_USER:-postgres}"

echo "[1/5] starting the database"
docker compose up -d --wait

echo "[2/5] loading the dataset"
# Skip the multi-minute reload when raw.bitcoin_prices is already populated.
existing_rows="$(
    docker compose exec -T db psql -tA -U "$user" -d "$db" \
        -c "select count(*) from raw.bitcoin_prices;" 2>/dev/null || echo 0
)"
if [ "${existing_rows:-0}" -gt 0 ]; then
    echo "raw.bitcoin_prices already has $existing_rows rows; skipping load"
else
    bash scripts/load_data.sh
fi

echo "[3/5] building and testing the dbt project"
uv run dbt deps
uv run dbt build

echo "[4/5] answering the questions"
bash scripts/print_answers.sh

echo "[5/5] writing the answer charts to docs/screenshots"
uv run python scripts/make_charts.py || echo "skipped charts (matplotlib missing? run 'uv sync')"
