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

    if [ -f "$PROJECT_ROOT/VERSION" ]; then test_pass "VERSION exists"; else test_fail "VERSION missing"; fi
    if [ -f "$PROJECT_ROOT/scripts/phoenix.sh" ]; then test_pass "Launcher exists"; else test_fail "Launcher missing"; fi
    if [ -f "$PROJECT_ROOT/lib/banner.sh" ]; then test_pass "Banner module exists"; else test_fail "Banner module missing"; fi
    if [ -f "$PROJECT_ROOT/lib/config.sh" ]; then test_pass "Config module exists"; else test_fail "Config module missing"; fi
    if [ -f "$PROJECT_ROOT/lib/logging.sh" ]; then test_pass "Logging module exists"; else test_fail "Logging module missing"; fi
    if [ -f "$PROJECT_ROOT/lib/discovery.sh" ]; then test_pass "Discovery module exists"; else test_fail "Discovery module missing"; fi
    if [ -f "$PROJECT_ROOT/lib/backup.sh" ]; then test_pass "Backup module exists"; else test_fail "Backup module missing"; fi
    if [ -f "$PROJECT_ROOT/examples/config.example.conf" ]; then test_pass "Example config exists"; else test_fail "Example config missing"; fi

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