#!/bin/bash

run_tests() {
    section "PROJECT PHOENIX TESTS"

    TESTS_PASSED=0
    TESTS_FAILED=0

    test_pass() {
        log_success "$1"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    }

    test_fail() {
        log_error "$1"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    }

    [ -f "$PROJECT_ROOT/VERSION" ] && test_pass "VERSION exists" || test_fail "VERSION missing"
    [ -f "$PROJECT_ROOT/scripts/phoenix.sh" ] && test_pass "Launcher exists" || test_fail "Launcher missing"
    [ -f "$PROJECT_ROOT/lib/banner.sh" ] && test_pass "Banner module exists" || test_fail "Banner module missing"
    [ -f "$PROJECT_ROOT/lib/config.sh" ] && test_pass "Config module exists" || test_fail "Config module missing"
    [ -f "$PROJECT_ROOT/lib/logging.sh" ] && test_pass "Logging module exists" || test_fail "Logging module missing"
    [ -f "$PROJECT_ROOT/lib/discovery.sh" ] && test_pass "Discovery module exists" || test_fail "Discovery module missing"
    [ -f "$PROJECT_ROOT/lib/backup.sh" ] && test_pass "Backup module exists" || test_fail "Backup module missing"
    [ -f "$PROJECT_ROOT/examples/config.example.conf" ] && test_pass "Example config exists" || test_fail "Example config missing"

    echo
    echo "Passed : $TESTS_PASSED"
    echo "Failed : $TESTS_FAILED"
    echo

    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo "PROJECT PHOENIX TEST STATUS: PASS"
        return 0
    else
        echo "PROJECT PHOENIX TEST STATUS: FAIL"
        return 1
    fi
}