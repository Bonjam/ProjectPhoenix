#!/bin/bash

run_tests() {
    local discovery_value
    local test_docker_source
    local test_docker_source_two
    local test_ssh_dir
    local test_ssh_key
    local test_ssh_key_two
    local test_temp_dir
    local recovery_analysis
    local recovery_output
    local restore_dry_run_command
    local restore_stats_fixture

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
    if [ -f "$PROJECT_ROOT/lib/recovery.sh" ]; then test_pass "Recovery module exists"; else test_fail "Recovery module missing"; fi
    if declare -F run_recovery >/dev/null 2>&1; then test_pass "Recovery command function exists"; else test_fail "Recovery command function missing"; fi
    if declare -F run_restore_dry_run >/dev/null 2>&1; then test_pass "Restore dry-run command function exists"; else test_fail "Restore dry-run command function missing"; fi
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
        test_docker_source_two="$test_temp_dir/docker source two"
        test_ssh_dir="$test_temp_dir/ssh"
        test_ssh_key="$test_ssh_dir/id_ed25519"
        test_ssh_key_two="$test_ssh_dir/id_rsa"
        mkdir -p "$test_docker_source"
        mkdir -p "$test_docker_source_two"
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

        touch "$test_ssh_key_two"

        mkdir -p "$test_temp_dir/recovery/service-one"
        mkdir -p "$test_temp_dir/recovery/service-two"
        mkdir -p "$test_temp_dir/recovery/inventory"
        mkdir -p "$test_temp_dir/recovery/manifests"
        mkdir -p "$test_temp_dir/recovery/restore"
        touch "$test_temp_dir/recovery/service-one/compose.yml"
        touch "$test_temp_dir/recovery/service-two/docker-compose.yaml"
        touch "$test_temp_dir/recovery/restore/README.md"

        recovery_analysis=$(recovery_analyse_local_directory "$test_temp_dir/recovery")
        if recovery_parse_analysis "$recovery_analysis" &&
            [ "$RECOVERY_TOP_LEVEL_ENTRIES" = "5" ] &&
            [ "$RECOVERY_COMPOSE_FILES" = "2" ] &&
            [ "${RECOVERY_COMPOSE_PROJECTS[*]}" = "service-one service-two" ] &&
            [ "$RECOVERY_INVENTORY" = "found" ] &&
            [ "$RECOVERY_MANIFEST" = "found" ] &&
            [ "$RECOVERY_RESTORE_GUIDE" = "found" ]; then
            test_pass "Recovery analysis parses local fixtures"
        else
            test_fail "Recovery analysis cannot parse local fixtures"
        fi

        if recovery_output=$(
            (PROJECT_ROOT="$test_temp_dir/missing-config"; run_recovery) 2>&1
        ); then
            test_fail "Recovery accepts missing configuration"
        elif grep -q "Missing config file" <<< "$recovery_output"; then
            test_pass "Recovery reports missing configuration clearly"
        else
            test_fail "Recovery missing configuration message is unclear"
        fi

        mkdir -p "$test_temp_dir/restore target"
        if restore_local_target_accessible "$test_temp_dir/restore target" &&
            ! restore_local_target_accessible "$test_temp_dir/missing restore target"; then
            test_pass "Restore dry run validates local targets without creating them"
        else
            test_fail "Restore dry run local target validation is unsafe"
        fi

        restore_dry_run_command=$(restore_execute_dry_run \
            echo "$test_temp_dir/mock key" test-user test-host \
            "/remote/backup" "$test_temp_dir/restore target")
        if grep -Fq -- "-avhn --stats" <<< "$restore_dry_run_command" &&
            grep -Fq -- "StrictHostKeyChecking=accept-new" <<< "$restore_dry_run_command" &&
            ! grep -Fq -- "--delete" <<< "$restore_dry_run_command"; then
            test_pass "Restore dry run uses safe rsync options"
        else
            test_fail "Restore dry run options are unsafe"
        fi

        restore_stats_fixture="Number of files: 12 (reg: 8, dir: 4)
Total transferred file size: 4,096 bytes"
        restore_parse_rsync_stats "$restore_stats_fixture"
        if [ "$RESTORE_DRY_RUN_FILE_COUNT" = "12" ] &&
            [ "$RESTORE_DRY_RUN_TRANSFER_SIZE" = "4,096 bytes" ]; then
            test_pass "Restore dry run parses rsync statistics"
        else
            test_fail "Restore dry run cannot parse rsync statistics"
        fi

        # shellcheck disable=SC2034 # Fixture consumed by setup_detect_docker_source.
        SETUP_DEFAULT_SOURCE=""
        SETUP_DISCOVERED_DOCKER_SOURCES=("$test_docker_source")
        setup_detect_docker_source <<< "" >/dev/null
        if [ "$SETUP_SOURCE" = "$test_docker_source" ]; then
            test_pass "Setup defaults to one discovered Docker source"
        else
            test_fail "Setup ignores one discovered Docker source"
        fi

        # shellcheck disable=SC2034 # Fixture consumed by setup_detect_docker_source.
        SETUP_DISCOVERED_DOCKER_SOURCES=("$test_docker_source" "$test_docker_source_two")
        setup_detect_docker_source <<< "2" >/dev/null
        if [ "$SETUP_SOURCE" = "$test_docker_source_two" ]; then
            test_pass "Setup selects from multiple Docker sources"
        else
            test_fail "Setup cannot select multiple Docker sources"
        fi

        # shellcheck disable=SC2034 # Fixture consumed by setup_ssh.
        SETUP_DEFAULT_SSH_KEY=""
        SETUP_DISCOVERED_SSH_KEYS=("$test_ssh_key")
        setup_ssh <<< "" >/dev/null
        if [ "$SETUP_SSH_KEY" = "$test_ssh_key" ]; then
            test_pass "Setup defaults to one discovered SSH key"
        else
            test_fail "Setup ignores one discovered SSH key"
        fi

        # shellcheck disable=SC2034 # Fixture consumed by setup_ssh.
        SETUP_DISCOVERED_SSH_KEYS=("$test_ssh_key" "$test_ssh_key_two")
        setup_ssh <<< "2" >/dev/null
        if [ "$SETUP_SSH_KEY" = "$test_ssh_key_two" ]; then
            test_pass "Setup selects from multiple SSH keys"
        else
            test_fail "Setup cannot select multiple SSH keys"
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
