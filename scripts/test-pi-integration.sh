#!/bin/bash

set -u

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRIVATE_CONFIG="$PROJECT_ROOT/test-local/pi-integration.conf"

pass() {
    echo "[PASS] $1"
}

warn() {
    echo "[WARN] $1"
}

fail() {
    echo "[FAIL] $1" >&2
    exit 1
}

if [ ! -f "$PRIVATE_CONFIG" ]; then
    fail "Private Pi integration configuration is missing."
fi

# shellcheck source=/dev/null
source "$PRIVATE_CONFIG"

for required_variable in PI_HOST PI_USER PI_DESTINATION PI_SSH_KEY; do
    if [ -z "${!required_variable:-}" ]; then
        fail "Required private setting $required_variable is missing or empty."
    fi
done
pass "Required private settings are present"

if ! command -v ssh >/dev/null 2>&1; then
    fail "SSH client is not installed."
fi
pass "SSH client exists"

if [ ! -f "$PI_SSH_KEY" ]; then
    fail "Configured SSH key file does not exist."
fi
pass "SSH key file exists"

warn "This check only tests connectivity and destination writability."

ssh_options=(
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o ConnectionAttempts=1
    -i "$PI_SSH_KEY"
)
remote_target="$PI_USER@$PI_HOST"

if ! ssh "${ssh_options[@]}" "$remote_target" true </dev/null >/dev/null 2>&1; then
    fail "Non-interactive SSH connection failed."
fi
pass "Non-interactive SSH connection succeeds"

if ! ssh "${ssh_options[@]}" "$remote_target" bash -s -- "$PI_DESTINATION" <<\REMOTE_CHECK >/dev/null 2>&1
destination=$1
[ -d "$destination" ]
REMOTE_CHECK
then
    fail "Remote destination does not exist."
fi
pass "Remote destination exists"

if ! ssh "${ssh_options[@]}" "$remote_target" bash -s -- "$PI_DESTINATION" <<\REMOTE_CHECK >/dev/null 2>&1
destination=$1
probe_file=""

cleanup() {
    if [ -n "$probe_file" ]; then
        rm -f -- "$probe_file"
    fi
}

trap cleanup EXIT HUP INT TERM
probe_file=$(mktemp -- "$destination/project-phoenix-test-XXXXXX") || exit 1
[ -f "$probe_file" ] || exit 1
[ ! -s "$probe_file" ] || exit 1
rm -f -- "$probe_file" || exit 1
probe_file=""
REMOTE_CHECK
then
    fail "Remote destination is not writable or the temporary probe could not be cleaned up."
fi
pass "Remote destination is writable and the temporary probe was removed"

echo "[PASS] Raspberry Pi integration checks completed successfully"
