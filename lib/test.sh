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
    local restore_confirm_command
    local restore_gate_output
    local protected_target
    local test_project_root="$PROJECT_ROOT"
    local verification_status
    local integrity_fixture
    local integrity_manifest_one
    local integrity_manifest_two
    local integrity_scenario
    local remote_reference_directory

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
    if declare -F run_restore_confirm >/dev/null 2>&1; then test_pass "Restore-confirm command function exists"; else test_fail "Restore-confirm command function missing"; fi
    if declare -F run_verify_restore >/dev/null 2>&1; then test_pass "Verify-restore command function exists"; else test_fail "Verify-restore command function missing"; fi
    if declare -F run_integrity_create >/dev/null 2>&1; then test_pass "Integrity-create command function exists"; else test_fail "Integrity-create command function missing"; fi
    if declare -F run_integrity_verify >/dev/null 2>&1; then test_pass "Integrity-verify command function exists"; else test_fail "Integrity-verify command function missing"; fi
    if declare -F integrity_generate_remote_reference >/dev/null 2>&1; then test_pass "Automatic remote integrity function exists"; else test_fail "Automatic remote integrity function missing"; fi
    if declare -F run_integrity_verify_remote >/dev/null 2>&1; then test_pass "Integrity-verify-remote command function exists"; else test_fail "Integrity-verify-remote command function missing"; fi
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

        if restore_target_is_safe "$test_temp_dir/restore target/" "$test_project_root" &&
            restore_target_is_safe "/tmp/project-phoenix-restore-test/" "$test_project_root"; then
            test_pass "Confirmed restore accepts safe nested targets"
        else
            test_fail "Confirmed restore rejects safe nested targets"
        fi

        for protected_target in "" / /bin /boot /dev /etc /home /lib /lib64 \
            /proc /root /run /sbin /sys /tmp /usr /var "$test_project_root/"
        do
            if restore_target_is_safe "$protected_target" "$test_project_root"; then
                test_fail "Confirmed restore accepts a protected target"
                protected_target="unsafe"
                break
            fi
        done
        if [ "$protected_target" != "unsafe" ]; then
            test_pass "Confirmed restore rejects protected targets"
        fi

        if restore_confirmation_matches "RESTORE PROJECT PHOENIX" &&
            ! restore_confirmation_matches "restore project phoenix" &&
            ! restore_confirmation_matches ""; then
            test_pass "Confirmed restore requires exact confirmation"
        else
            test_fail "Confirmed restore confirmation is not exact"
        fi

        if restore_gate_output=$(restore_execute_confirmed_if_ready \
            1 "RESTORE PROJECT PHOENIX" echo mock-key mock-user mock-host \
            /remote/backup "$test_temp_dir/restore target" 2>&1); then
            test_fail "Confirmed restore runs after a failed dry run"
        elif [ -z "$restore_gate_output" ]; then
            test_pass "Dry-run failure prevents confirmed rsync"
        else
            test_fail "Dry-run failure gate produced unexpected output"
        fi

        restore_confirm_command=$(restore_execute_confirmed_if_ready \
            0 "RESTORE PROJECT PHOENIX" echo mock-key mock-user mock-host \
            /remote/backup "$test_temp_dir/restore target")
        if grep -Fq -- "-avh --stats" <<< "$restore_confirm_command" &&
            ! grep -Fq -- "-avhn" <<< "$restore_confirm_command" &&
            ! grep -Fq -- "--delete" <<< "$restore_confirm_command" &&
            ! grep -Fq -- "--remove-source-files" <<< "$restore_confirm_command"; then
            test_pass "Confirmed restore uses safe real rsync options"
        else
            test_fail "Confirmed restore rsync options are unsafe"
        fi

        ln -s "$test_temp_dir/recovery/missing-target" \
            "$test_temp_dir/recovery/broken-link"
        mkdir -p "$test_temp_dir/recovery/empty-service"
        verification_analyse_source "$test_temp_dir/recovery"

        if [ "$VERIFY_COMPOSE_FILES" = "2" ] &&
            [ "${VERIFY_COMPOSE_PROJECTS[*]}" = "service-one service-two" ]; then
            test_pass "Restore verification counts Compose fixtures"
        else
            test_fail "Restore verification Compose analysis is incorrect"
        fi
        if [ "$VERIFY_BROKEN_SYMLINKS" = "1" ]; then
            test_pass "Restore verification detects broken symlinks"
        else
            test_fail "Restore verification misses broken symlinks"
        fi
        if [ "$VERIFY_EMPTY_TOP_LEVEL_DIRECTORIES" -ge 1 ]; then
            test_pass "Restore verification detects empty top-level directories"
        else
            test_fail "Restore verification misses empty top-level directories"
        fi

        verification_compare_expected_services \
            "$test_temp_dir/recovery" "service-one service-two"
        if [ "$VERIFY_EXPECTED_FOUND" = "2" ] &&
            [ "$VERIFY_EXPECTED_MISSING" = "0" ]; then
            test_pass "Restore verification finds all expected services"
        else
            test_fail "Restore verification expected-service match is incorrect"
        fi

        verification_compare_expected_services \
            "$test_temp_dir/recovery" "service-one missing-service"
        if [ "$VERIFY_EXPECTED_FOUND" = "1" ] &&
            [ "$VERIFY_EXPECTED_MISSING" = "1" ] &&
            [ "${VERIFY_MISSING_SERVICES[*]}" = "missing-service" ]; then
            test_pass "Restore verification detects missing expected services"
        else
            test_fail "Restore verification misses absent expected services"
        fi

        if [ "$(printf "first\nsecond\n" | verification_count_records)" = "2" ]; then
            test_pass "Restore verification parses unreadable-item records"
        else
            test_fail "Restore verification unreadable-item parsing failed"
        fi

        VERIFY_EXPECTED_MISSING=0
        # shellcheck disable=SC2034 # Fixture consumed by verification_evaluate_status.
        VERIFY_EXPECTED_SKIPPED="no"
        # shellcheck disable=SC2034 # Fixture consumed by verification_evaluate_status.
        VERIFY_UNREADABLE_FILES=0
        # shellcheck disable=SC2034 # Fixture consumed by verification_evaluate_status.
        VERIFY_UNREADABLE_DIRECTORIES=0
        VERIFY_BROKEN_SYMLINKS=0
        VERIFY_EMPTY_TOP_LEVEL_DIRECTORIES=0
        verification_status=$(verification_evaluate_status)
        if [ "$verification_status" = "PASS" ]; then
            test_pass "Restore verification passes complete fixtures"
        else
            test_fail "Restore verification status evaluation is incorrect"
        fi

        integrity_fixture="$test_temp_dir/integrity fixture"
        integrity_manifest_one="$test_temp_dir/integrity-one.txt"
        integrity_manifest_two="$test_temp_dir/integrity-two.txt"
        mkdir -p "$integrity_fixture/folder with spaces"
        printf "alpha\n" > "$integrity_fixture/folder with spaces/file one.txt"
        printf "dash\n" > "$integrity_fixture/-leading-name"
        ln -s "folder with spaces/file one.txt" "$integrity_fixture/link name"
        integrity_generate_manifest "$integrity_fixture" "$integrity_manifest_one" "fixed-time"
        integrity_generate_manifest "$integrity_fixture" "$integrity_manifest_two" "fixed-time"
        if cmp -s "$integrity_manifest_one" "$integrity_manifest_two"; then
            test_pass "Integrity manifests are deterministic"
        else
            test_fail "Integrity manifests are not deterministic"
        fi
        if integrity_compare_manifests "$integrity_manifest_one" "$integrity_manifest_two" &&
            [ "${#INTEGRITY_MISSING_FILES[@]}" -eq 0 ] &&
            [ "${#INTEGRITY_CHANGED_LINK_TARGETS[@]}" -eq 0 ]; then
            test_pass "Matching integrity fixtures pass"
        else
            test_fail "Matching integrity fixtures fail"
        fi

        integrity_scenario="$test_temp_dir/integrity changed"
        cp -a -- "$integrity_fixture" "$integrity_scenario"
        printf "larger content\n" > "$integrity_scenario/-leading-name"
        rm -f -- "$integrity_scenario/link name"
        ln -s "different-target" "$integrity_scenario/link name"
        rm -f -- "$integrity_scenario/folder with spaces/file one.txt"
        printf "new\n" > "$integrity_scenario/unexpected file"
        integrity_generate_manifest "$integrity_scenario" "$integrity_manifest_two" "fixed-time"
        integrity_compare_manifests "$integrity_manifest_one" "$integrity_manifest_two"
        if [ "${#INTEGRITY_MISSING_FILES[@]}" -eq 1 ] &&
            [ "${#INTEGRITY_UNEXPECTED_FILES[@]}" -eq 1 ] &&
            [ "${#INTEGRITY_CHANGED_SIZES[@]}" -eq 1 ] &&
            [ "${#INTEGRITY_CHANGED_HASHES[@]}" -eq 1 ] &&
            [ "${#INTEGRITY_CHANGED_LINK_TARGETS[@]}" -eq 1 ]; then
            test_pass "Integrity verification detects file and link changes"
        else
            test_fail "Integrity verification misses file or link changes"
        fi

        printf "not a manifest\n" > "$test_temp_dir/malformed-integrity.txt"
        if integrity_compare_manifests \
            "$test_temp_dir/malformed-integrity.txt" "$integrity_manifest_one"; then
            test_fail "Integrity verification accepts malformed manifests"
        else
            test_pass "Integrity verification rejects malformed manifests clearly"
        fi

        if run_backup_integrity_hook 0 true &&
            [ "$BACKUP_INTEGRITY_STATUS" = "success" ]; then
            test_pass "Clean backup triggers integrity generation"
        else
            test_fail "Clean backup skips integrity generation"
        fi
        if run_backup_integrity_hook 23 true &&
            [ "$BACKUP_INTEGRITY_STATUS" = "success" ]; then
            test_pass "Rsync warning backup triggers integrity generation"
        else
            test_fail "Rsync warning backup skips integrity generation"
        fi
        if run_backup_integrity_hook 12 false &&
            [ "$BACKUP_INTEGRITY_STATUS" = "skipped" ]; then
            test_pass "Genuine rsync failure prevents integrity generation"
        else
            test_fail "Genuine rsync failure attempts integrity generation"
        fi
        if run_backup_integrity_hook 0 false; then
            test_fail "Integrity failure is reported as success"
        elif [ "$BACKUP_INTEGRITY_STATUS" = "failed" ]; then
            backup_set_outcome_status 0 "$BACKUP_INTEGRITY_STATUS"
            if [ "$BACKUP_HISTORY_STATUS" = "partial" ] &&
                [[ "$BACKUP_HISTORY_DETAILS" == *"copied cleanly"* ]] &&
                [[ "$BACKUP_HISTORY_DETAILS" == *"integrity generation failed"* ]]; then
                test_pass "Integrity failure preserves clean copy outcome"
            else
                test_fail "Clean copy and integrity failure history is unclear"
            fi
        else
            test_fail "Integrity failure corrupts backup status"
        fi

        run_backup_integrity_hook 23 true
        backup_set_outcome_status 23 "$BACKUP_INTEGRITY_STATUS"
        if [ "$BACKUP_HISTORY_STATUS" = "completed-with-warnings" ] &&
            [[ "$BACKUP_HISTORY_DETAILS" == *"rsync warnings"* ]] &&
            [[ "$BACKUP_HISTORY_DETAILS" == *"integrity manifest completed"* ]]; then
            test_pass "Warning copy and integrity success preserve both outcomes"
        else
            test_fail "Warning copy history loses copy or integrity outcome"
        fi

        run_backup_integrity_hook 23 false || true
        backup_set_outcome_status 23 "$BACKUP_INTEGRITY_STATUS"
        if [ "$BACKUP_HISTORY_STATUS" = "partial" ] &&
            [[ "$BACKUP_HISTORY_DETAILS" == *"rsync warnings"* ]] &&
            [[ "$BACKUP_HISTORY_DETAILS" == *"integrity generation failed"* ]]; then
            test_pass "Warning copy and integrity failure preserve both outcomes"
        else
            test_fail "Partial backup history loses copy or integrity outcome"
        fi

        remote_reference_directory="$test_temp_dir/local manifests"
        mkdir -p "$remote_reference_directory/integrity/remote"
        printf "previous reference\n" > \
            "$remote_reference_directory/integrity/remote/latest.txt"
        integrity_store_local_remote_reference \
            "$integrity_manifest_one" "integrity-fixed.txt" \
            "$remote_reference_directory"
        if [ -f "$remote_reference_directory/integrity/remote/latest.txt" ] &&
            [ ! -L "$remote_reference_directory/integrity/remote/latest.txt" ] &&
            cmp -s "$integrity_manifest_one" \
                "$remote_reference_directory/integrity/remote/latest.txt"; then
            test_pass "Remote latest integrity reference is copied safely"
        else
            test_fail "Remote latest integrity reference is not a safe copy"
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
