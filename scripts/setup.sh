#!/usr/bin/env bash
# One-time developer setup: create the uv venv, install the dbt packages, and (if
# direnv is present) enable the committed .envrc so dbt and sqlfluff run without a
# prefix. Not required to run the pipeline: `bash run.sh` does its own setup.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
export DBT_PROFILES_DIR="$(pwd)"

uv sync
uv run dbt deps

echo
if command -v direnv >/dev/null 2>&1; then
    direnv allow
    echo "Setup complete. direnv is enabled: dbt and sqlfluff run without a prefix once you cd in."
else
    echo "Setup complete. Run dbt with 'uv run dbt ...', or 'source .venv/bin/activate' for a bare 'dbt'."
    echo "Optional: install direnv (https://direnv.net) to drop the prefix automatically."
fi
