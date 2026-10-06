#!/data/data/com.termux/files/usr/bin/sh
# Run with `sh scripts/smoke-test.sh /path/to/herdr` in Termux.
# All server/session state is isolated; existing Herdr sessions are untouched.
set -eu

herdr_bin=${1:-herdr}
herdr_bin=$(command -v "$herdr_bin")
case "$herdr_bin" in
    /*) ;;
    *) herdr_bin=$(pwd)/$herdr_bin ;;
esac
command -v timeout >/dev/null 2>&1 || {
    echo 'timeout is required (pkg install coreutils).' >&2
    exit 1
}

smoke_root=$(mktemp -d "${TMPDIR:-/tmp}/ht.XXXXXX")
server_pid=
smoke_ok=false
cleanup() {
    if [ -n "$server_pid" ]; then
        h server stop >/dev/null 2>&1 || true
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    if [ "$smoke_ok" = true ]; then
        rm -rf "$smoke_root"
    else
        echo "Smoke test failed; logs retained at $smoke_root" >&2
        cat "$smoke_root/server.log" >&2 2>/dev/null || true
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$smoke_root/c/herdr" "$smoke_root/r" "$smoke_root/cache" "$smoke_root/data"
cat > "$smoke_root/c/herdr/config.toml" <<'CONFIG'
onboarding = false
[update]
version_check = false
manifest_check = false
CONFIG

# Use a subshell to avoid changing the caller's environment, and clear inherited
# pane routing so this test cannot accidentally operate on a user's session.
h() (
    unset HERDR_SOCKET_PATH HERDR_CLIENT_SOCKET_PATH HERDR_ENV HERDR_SESSION
    export XDG_CONFIG_HOME="$smoke_root/c" XDG_RUNTIME_DIR="$smoke_root/r"
    export XDG_CACHE_HOME="$smoke_root/cache" XDG_DATA_HOME="$smoke_root/data"
    export HERDR_DISABLE_SOUND=1
    timeout -k 2 30 "$herdr_bin" --session smoke "$@"
)

version=$(h --version)
printf '%s\n' "$version"
case "$version" in
    'herdr 0.9.3'*) ;;
    *) echo 'Unexpected Herdr version.' >&2; exit 1 ;;
esac

# Start the foreground server directly, without placing a timeout around its
# lifetime. Individual requests below remain bounded.
(
    unset HERDR_SOCKET_PATH HERDR_CLIENT_SOCKET_PATH HERDR_ENV HERDR_SESSION
    export XDG_CONFIG_HOME="$smoke_root/c" XDG_RUNTIME_DIR="$smoke_root/r"
    export XDG_CACHE_HOME="$smoke_root/cache" XDG_DATA_HOME="$smoke_root/data"
    export HERDR_DISABLE_SOUND=1
    exec "$herdr_bin" --session smoke server
) > "$smoke_root/server.log" 2>&1 &
server_pid=$!

attempt=0
until h api snapshot > "$smoke_root/snapshot.json" 2> "$smoke_root/cli.log"; do
    if ! kill -0 "$server_pid" 2>/dev/null || [ "$attempt" -ge 30 ]; then
        cat "$smoke_root/cli.log" >&2
        exit 1
    fi
    attempt=$((attempt + 1))
    sleep 1
done

h workspace create --label smoke --cwd "$smoke_root" > "$smoke_root/workspace.json"
pane_id=$(sed -n 's/.*"pane_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$smoke_root/workspace.json" | head -n 1)
[ -n "$pane_id" ] || {
    cat "$smoke_root/workspace.json" >&2
    echo 'Workspace did not produce a shell pane.' >&2
    exit 1
}

# The exact marker does not occur in the submitted command, so terminal echo
# cannot be mistaken for a command that actually executed in the PTY shell.
h pane run "$pane_id" "printf 'HERDR_%s_%s\\n' TERMUX SMOKE_OK" >/dev/null
h pane wait-output "$pane_id" --match HERDR_TERMUX_SMOKE_OK --timeout 15000 > "$smoke_root/pane.json"
h pane process-info --pane "$pane_id" > "$smoke_root/process.json"
grep -q '"shell_pid"[[:space:]]*:[[:space:]]*[0-9]' "$smoke_root/process.json" || {
    cat "$smoke_root/process.json" >&2
    echo 'Pane process query did not report a shell PID.' >&2
    exit 1
}
h session list --json > "$smoke_root/sessions.json"
grep -q '"running"[[:space:]]*:[[:space:]]*true' "$smoke_root/sessions.json" || {
    cat "$smoke_root/sessions.json" >&2
    echo 'Named session was not reported as running.' >&2
    exit 1
}
h server stop

attempt=0
while kill -0 "$server_pid" 2>/dev/null; do
    [ "$attempt" -lt 15 ] || { echo 'Server did not stop.' >&2; exit 1; }
    attempt=$((attempt + 1))
    sleep 1
done
wait "$server_pid"
server_pid=
h session delete smoke --json >/dev/null
smoke_ok=true
echo 'PASS: version, named server/session, PTY shell command, process query, and shutdown.'
