#!/usr/bin/env bash
# Shared shell helpers, sourced by run.sh and the scripts/ entrypoints.
# Portable across macOS and Linux/WSL2: no GNU-only flags, no `readlink -f`
# (absent on stock macOS).

# Resolve the absolute directory of a script, following symlinks, without
# `readlink -f`. Pass the caller's "${BASH_SOURCE[0]}" (or "$0").
script_dir() {
    src="$1"
    while [ -h "$src" ]; do
        dir="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
        src="$(readlink "$src")"
        case "$src" in
            /*) ;;
            *) src="$dir/$src" ;;
        esac
    done
    cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd
}

# Echo the path to the single dataset CSV in the given directory (project root),
# or fail with a clear message. The dataset is never committed; the assignment
# assumes it is present in the project root at run time.
find_dataset() {
    root="$1"
    for candidate in "$root"/*.csv; do
        if [ -e "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    echo "error: no dataset CSV found in '$root'. Place the Binance 1s CSV in the project root and re-run." >&2
    return 1
}

# Block until the Postgres container answers, or fail after a bounded number of
# attempts. Used by run.sh after `docker compose up`. Relies on the compose
# service being named 'db'.
wait_for_postgres() {
    retries="${1:-30}"
    user="${POSTGRES_USER:-postgres}"
    attempt=0
    while [ "$attempt" -lt "$retries" ]; do
        if docker compose exec -T db pg_isready -U "$user" >/dev/null 2>&1; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done
    echo "error: postgres did not become ready after ${retries}s" >&2
    return 1
}
