#!/usr/bin/env bash
# Shared helpers sourced by run.sh and the scripts in this directory.

# Absolute directory of a script, resolving symlinks (portable: avoids readlink -f).
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

# Path to the dataset CSV in the project root, or fail with a clear message.
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

# Wait for the Postgres container to accept connections, then give up after a bound.
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
