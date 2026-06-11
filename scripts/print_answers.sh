#!/usr/bin/env bash
# Compile the answer analysis and run it against the built marts, printing one
# labeled row per question. Shared by `make answers` and run.sh.
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$dir/.." && pwd)"
# shellcheck source=scripts/lib.sh
. "$dir/lib.sh"
cd "$root"

export DBT_PROFILES_DIR="$root"
db="${POSTGRES_DB:-bitcoin}"
user="${POSTGRES_USER:-postgres}"

# Analyses are not materialized, so compile to get runnable SQL, then execute it.
uv run dbt compile --select answer_strategy_questions >/dev/null
compiled="target/compiled/alpaca_takehome/analyses/answer_strategy_questions.sql"
if [ ! -f "$compiled" ]; then
    echo "error: compiled analysis not found at $compiled" >&2
    exit 1
fi

echo
echo "Strategy answers (UTC hours):"
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U "$user" -d "$db" -P pager=off < "$compiled"
