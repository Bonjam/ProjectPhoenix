#!/bin/bash

set -u

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

PASSED=0
FAILED=0

pass() {
    echo "[PASS] $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo "[FAIL] $1"
    FAILED=$((FAILED + 1))
}

run_command_test() {
    local name="$1"
    local command="$2"

    echo
    echo "Testing: $name"
    echo "-------------------------------------------------------------"

    if eval "$command" >/tmp/phoenix-test-output.log 2>&1; then
        pass "$name"
    else
        fail "$name"
        cat /tmp/phoenix-test-output.log
    fi
}

echo "============================================================="
echo "                 PROJECT PHOENIX DEV TEST"
echo "============================================================="
echo

echo "Project root: $PROJECT_ROOT"
echo

echo "Checking Bash files..."
echo "-------------------------------------------------------------"

if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck scripts/*.sh lib/*.sh; then
        pass "ShellCheck"
    else
        fail "ShellCheck"
    fi
else
    echo "[WARN] ShellCheck not installed. Skipping."
fi

run_command_test "help" "bash scripts/phoenix.sh help"
run_command_test "banner" "bash scripts/phoenix.sh banner"
run_command_test "info" "bash scripts/phoenix.sh info"
run_command_test "requirements" "bash scripts/phoenix.sh requirements"
run_command_test "test" "bash scripts/phoenix.sh test"
run_command_test "doctor" "bash scripts/phoenix.sh doctor"
run_command_test "discovery" "bash scripts/phoenix.sh discovery"

if [ -f test-local/pi-integration.conf ]; then
    run_command_test "Pi integration" "bash scripts/test-pi-integration.sh"
else
    echo
    echo "[SKIP] Pi integration (private configuration not found)"
fi

echo
echo "============================================================="
echo "                       TEST SUMMARY"
echo "============================================================="
echo
echo "Passed : $PASSED"
echo "Failed : $FAILED"
echo

rm -f /tmp/phoenix-test-output.log

if [ "$FAILED" -eq 0 ]; then
    echo "PROJECT PHOENIX DEV TEST: PASS"
    exit 0
else
    echo "PROJECT PHOENIX DEV TEST: FAIL"
    exit 1
fi
