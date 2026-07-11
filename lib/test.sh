#!/bin/bash

run_tests() {
    local discovery_value
    local test_docker_source
    local test_ssh_dir
    local test_ssh_key
    local test_temp_dir

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

    discovery_value=$(discovery_get_os_name)
    if [ -n "$discovery_value" ]; then test_pass "Discovery OS name available"; else test_fail "Discovery OS name missing"; fi

    discovery_value=$(discovery_get_kernel)
    if [ -n "$discovery_value" ]; then test_pass "Discovery kernel available"; else test_fail "Discovery kernel missing"; fi

    discovery_value=$(discovery_get_architecture)
    if [ -n "$discovery_value" ]; then test_pass "Discovery architecture available"; else test_fail "Discovery architecture missing"; fi

    if discovery_has_command bash; then test_pass "Discovery finds bash"; else test_fail "Discovery cannot find bash"; fi

    if discovery_has_command project-phoenix-command-that-does-not-exist; then
        test_fail "Discovery reports nonexistent command"
    else
        test_pass "Discovery rejects nonexistent command"
    fi

    if declare -F setup_system_analysis >/dev/null 2>&1; then
        test_pass "Setup system analysis available"
    else
        test_fail "Setup system analysis missing"
    fi

    if test_temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/project-phoenix-test.XXXXXX"); then
        test_docker_source="$test_temp_dir/docker source"
        test_ssh_dir="$test_temp_dir/ssh"
        test_ssh_key="$test_ssh_dir/id_ed25519"
        mkdir -p "$test_docker_source"
        mkdir -p "$test_ssh_dir"
        touch "$test_ssh_key"

        discovery_value=$(discovery_find_common_docker_sources \
            "$test_temp_dir/not present" \
            "$test_docker_source")

        if [ "$discovery_value" = "$test_docker_source" ]; then
            test_pass "Discovery accepts supplied Docker source candidates"
        else
            test_fail "Discovery rejects supplied Docker source candidates"
        fi

        discovery_value=$(discovery_find_ssh_keys "$test_ssh_dir")

        if [ "$discovery_value" = "$test_ssh_key" ]; then
            test_pass "Discovery reports common SSH key paths"
        else
            test_fail "Discovery misses common SSH key paths"
        fi

        rm -rf "$test_temp_dir"
    else
        test_fail "Unable to create temporary discovery test directory"
    fi

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
