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
    local verification_legacy_fixture verification_policy_fixture verification_source_fixture service_mode
    local integrity_fixture
    local integrity_manifest_one
    local integrity_manifest_two
    local integrity_scenario
    local remote_reference_directory
    local integrity_fetch_root
    local integrity_remote_fixture
    local integrity_changed_fixture integrity_collision_root integrity_symlink_root
    local retention_directory
    local retention_mismatch_directory
    local retention_symlink_directory
    local retention_mock_output
    local retention_index
    local cleanup_directory cleanup_changed_directory cleanup_script cleanup_result
    local -a cleanup_expected=() cleanup_changed_expected=()
    local health_now health_remote_fixture
    local metadata_inventory metadata_guide metadata_root
    local inventory_source inventory_report
    local lock_path lock_token lock_result current_process_start signal_name
    local lock_cleanup_output backup_outcome_label

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


    test_later_exit_handler() {
        # shellcheck disable=SC2317 # Invoked indirectly by the trap registry.
        printf "later trap ran\n" > "$test_temp_dir/later-trap-marker"
    }

    test_write_backup_lock_metadata() {
        local path="$1" pid="$2" process_start="$3" owner_token="$4"
        {
            printf "pid=%s\n" "$pid"
            printf "started=%s\n" "2026-07-13T12:00:00Z"
            printf "hostname=%s\n" "fixture-host"
            printf "process_start=%s\n" "$process_start"
            printf "owner_token=%s\n" "$owner_token"
        } > "$path"
    }
    if [ -f "$PROJECT_ROOT/VERSION" ]; then test_pass "VERSION exists"; else test_fail "VERSION missing"; fi
    if [ -f "$PROJECT_ROOT/scripts/phoenix.sh" ]; then test_pass "Launcher exists"; else test_fail "Launcher missing"; fi
    if [ -f "$PROJECT_ROOT/lib/banner.sh" ]; then test_pass "Banner module exists"; else test_fail "Banner module missing"; fi
    if [ -f "$PROJECT_ROOT/lib/config.sh" ]; then test_pass "Config module exists"; else test_fail "Config module missing"; fi
    if [ -f "$PROJECT_ROOT/lib/logging.sh" ]; then test_pass "Logging module exists"; else test_fail "Logging module missing"; fi
    if [ -f "$PROJECT_ROOT/lib/discovery.sh" ]; then test_pass "Discovery module exists"; else test_fail "Discovery module missing"; fi
    if [ -f "$PROJECT_ROOT/lib/backup.sh" ]; then test_pass "Backup module exists"; else test_fail "Backup module missing"; fi
    if [ -f "$PROJECT_ROOT/lib/service-policy.sh" ] && declare -F service_policy_classify_source >/dev/null 2>&1; then test_pass "Service-policy module is loaded"; else test_fail "Service-policy module is not loaded"; fi
    if [ -f "$PROJECT_ROOT/lib/recovery.sh" ]; then test_pass "Recovery module exists"; else test_fail "Recovery module missing"; fi
    if declare -F run_recovery >/dev/null 2>&1; then test_pass "Recovery command function exists"; else test_fail "Recovery command function missing"; fi
    if declare -F run_restore_dry_run >/dev/null 2>&1; then test_pass "Restore dry-run command function exists"; else test_fail "Restore dry-run command function missing"; fi
    if declare -F run_restore_confirm >/dev/null 2>&1; then test_pass "Restore-confirm command function exists"; else test_fail "Restore-confirm command function missing"; fi
    if declare -F run_verify_restore >/dev/null 2>&1; then test_pass "Verify-restore command function exists"; else test_fail "Verify-restore command function missing"; fi
    if declare -F run_integrity_create >/dev/null 2>&1; then test_pass "Integrity-create command function exists"; else test_fail "Integrity-create command function missing"; fi
    if declare -F run_integrity_verify >/dev/null 2>&1; then test_pass "Integrity-verify command function exists"; else test_fail "Integrity-verify command function missing"; fi
    if declare -F integrity_generate_remote_reference >/dev/null 2>&1; then test_pass "Automatic remote integrity function exists"; else test_fail "Automatic remote integrity function missing"; fi
    if declare -F run_integrity_verify_remote >/dev/null 2>&1; then test_pass "Integrity-verify-remote command function exists"; else test_fail "Integrity-verify-remote command function missing"; fi
    if declare -F run_integrity_fetch_remote >/dev/null 2>&1; then test_pass "Integrity-fetch-remote command function exists"; else test_fail "Integrity-fetch-remote command function missing"; fi
    if declare -F run_integrity_retention >/dev/null 2>&1; then test_pass "Integrity-retention command function exists"; else test_fail "Integrity-retention command function missing"; fi
    if declare -F run_integrity_cleanup >/dev/null 2>&1; then test_pass "Integrity-cleanup command function exists"; else test_fail "Integrity-cleanup command function missing"; fi
    if declare -F run_health >/dev/null 2>&1; then test_pass "Health command function exists"; else test_fail "Health command function missing"; fi
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

        mkdir -p "$test_temp_dir/backup locks"
        lock_path="$test_temp_dir/backup locks/new.lock"
        if backup_lock_acquire_path "$lock_path" &&
            [ -f "$lock_path" ] && [ ! -L "$lock_path" ] &&
            grep -Fxq "pid=$$" "$lock_path" &&
            grep -q '^started=' "$lock_path"; then
            lock_token="$BACKUP_LOCK_OWNER_TOKEN"
            test_pass "New PID-aware backup lock acquisition succeeds"
            backup_lock_cleanup_path "$lock_path" "$lock_token" || true
        else
            test_fail "New backup lock acquisition fails"
        fi

        lock_path="$test_temp_dir/backup locks/active.lock"
        if backup_lock_acquire_path "$lock_path"; then
            lock_token="$BACKUP_LOCK_OWNER_TOKEN"
            if backup_lock_acquire_path "$lock_path" true; then
                test_fail "Active matching backup process permits a second lock"
            elif [ "$?" -eq 1 ] && [ "$BACKUP_LOCK_ACTIVE_PID" = "$$" ]; then
                test_pass "Active matching backup process blocks a second lock"
            else
                test_fail "Active backup lock is not reported accurately"
            fi
            backup_lock_cleanup_path "$lock_path" "$lock_token" || true
        else
            test_fail "Unable to prepare active backup lock fixture"
        fi

        lock_path="$test_temp_dir/backup locks/dead.lock"
        test_write_backup_lock_metadata "$lock_path" 99999999 1 dead-owner
        if backup_lock_acquire_path "$lock_path" &&
            [ "$BACKUP_LOCK_RECOVERED_PID" = 99999999 ]; then
            lock_token="$BACKUP_LOCK_OWNER_TOKEN"
            test_pass "Dead PID backup lock is recovered"
            backup_lock_cleanup_path "$lock_path" "$lock_token" || true
        else
            test_fail "Dead PID backup lock is not recovered"
        fi

        lock_path="$test_temp_dir/backup locks/malformed.lock"
        printf "pid=not-a-pid\nstarted=unknown\n" > "$lock_path"
        if backup_lock_acquire_path "$lock_path" &&
            [ "$BACKUP_LOCK_RECOVERED_PID" = not-a-pid ]; then
            lock_token="$BACKUP_LOCK_OWNER_TOKEN"
            test_pass "Malformed PID backup lock is recovered safely"
            backup_lock_cleanup_path "$lock_path" "$lock_token" || true
        else
            test_fail "Malformed PID backup lock handling is unsafe"
        fi

        lock_path="$test_temp_dir/backup locks/reused-pid.lock"
        current_process_start=$(backup_lock_process_start "$$")
        test_write_backup_lock_metadata "$lock_path" "$$" "$current_process_start" reused-owner
        if backup_lock_acquire_path "$lock_path" &&
            [ "$BACKUP_LOCK_RECOVERED_PID" = "$$" ]; then
            lock_token="$BACKUP_LOCK_OWNER_TOKEN"
            test_pass "Live unrelated reused PID is treated as stale"
            backup_lock_cleanup_path "$lock_path" "$lock_token" || true
        else
            test_fail "PID reuse check relies only on process liveness"
        fi

        touch "$test_temp_dir/backup locks/symlink-target"
        lock_path="$test_temp_dir/backup locks/symlink.lock"
        ln -s "$test_temp_dir/backup locks/symlink-target" "$lock_path"
        lock_result=0
        backup_lock_acquire_path "$lock_path" || lock_result=$?
        if [ "$lock_result" -eq 2 ] && [ -L "$lock_path" ]; then
            test_pass "Symlink backup lock is rejected without removal"
        else
            test_fail "Symlink backup lock is accepted or altered"
        fi
        rm -f -- "$lock_path"

        lock_path="$test_temp_dir/backup locks/owned-cleanup.lock"
        if backup_lock_acquire_path "$lock_path"; then
            lock_token="$BACKUP_LOCK_OWNER_TOKEN"
            if backup_lock_cleanup_path "$lock_path" "$lock_token" &&
                [ ! -e "$lock_path" ]; then
                test_pass "Cleanup removes the current process lock"
            else
                test_fail "Cleanup leaves the current process lock"
            fi
        else
            test_fail "Unable to prepare owned cleanup fixture"
        fi

        lock_path="$test_temp_dir/backup locks/other-owner.lock"
        if backup_lock_acquire_path "$lock_path"; then
            lock_token="$BACKUP_LOCK_OWNER_TOKEN"
            if ! backup_lock_cleanup_path "$lock_path" different-owner &&
                [ -f "$lock_path" ]; then
                test_pass "Cleanup does not remove another owner's lock"
            else
                test_fail "Cleanup removes a lock with a different owner token"
            fi
            backup_lock_cleanup_path "$lock_path" "$lock_token" || true
        else
            test_fail "Unable to prepare other-owner cleanup fixture"
        fi

        for signal_name in INT TERM; do
            lock_path="$test_temp_dir/backup locks/signal-$signal_name.lock"
            if (
                backup_lock_acquire_path "$lock_path"
                # shellcheck disable=SC2034 # Fixture consumed by backup_lock_signal_cleanup.
                LOCKFILE="$lock_path"
                backup_lock_signal_cleanup "$signal_name"
                [ ! -e "$lock_path" ]
            ); then
                test_pass "$signal_name cleanup helper removes its owned lock"
            else
                test_fail "$signal_name cleanup helper does not remove its owned lock"
            fi
        done

        lock_path="$test_temp_dir/backup locks/atomic.lock"
        if backup_lock_acquire_path "$lock_path"; then
            lock_token="$BACKUP_LOCK_OWNER_TOKEN"
            lock_result=0
            backup_lock_acquire_path "$lock_path" true || lock_result=$?
            if [ "$lock_result" -eq 1 ] && [ -f "$lock_path" ]; then
                test_pass "Atomic backup lock permits only one acquisition"
            else
                test_fail "Two simulated backup lock acquisitions both succeed"
            fi
            backup_lock_cleanup_path "$lock_path" "$lock_token" || true
        else
            test_fail "Unable to prepare atomic acquisition fixture"
        fi
        for lock_result in 0 23 12; do
            case "$lock_result" in
                0) backup_outcome_label="clean" ;;
                23) backup_outcome_label="warning" ;;
                *) backup_outcome_label="failed" ;;
            esac
            lock_path="$test_temp_dir/backup locks/$backup_outcome_label-completion.lock"
            if (
                backup_lock_acquire_path "$lock_path"
                LOCKFILE="$lock_path"
                export LOCKFILE
                backup_lock_finalize_status "$lock_result" "$backup_outcome_label completion"
                [ "$?" -eq "$lock_result" ] && [ ! -e "$lock_path" ]
            ); then
                test_pass "$backup_outcome_label backup completion removes its lock"
            else
                test_fail "$backup_outcome_label backup completion leaves its lock"
            fi
        done

        lock_path="$test_temp_dir/backup locks/exit-handler.lock"
        if (
            backup_lock_acquire_path "$lock_path"
            LOCKFILE="$lock_path"
            export LOCKFILE
            backup_lock_install_traps
            phoenix_trap_dispatch EXIT
            [ ! -e "$lock_path" ]
        ); then
            test_pass "EXIT safety handler removes an owned lock"
        else
            test_fail "EXIT safety handler leaves an owned lock"
        fi

        rm -f -- "$test_temp_dir/later-trap-marker"
        lock_path="$test_temp_dir/backup locks/composed-exit.lock"
        if (
            backup_lock_acquire_path "$lock_path"
            LOCKFILE="$lock_path"
            export LOCKFILE
            backup_lock_install_traps
            phoenix_trap_register later-exit test_later_exit_handler EXIT
            phoenix_trap_dispatch EXIT
            [ ! -e "$lock_path" ] && [ -f "$test_temp_dir/later-trap-marker" ]
        ); then
            test_pass "Later EXIT handler registration preserves lock cleanup"
        else
            test_fail "Later EXIT handler registration suppresses lock cleanup"
        fi

        rm -f -- "$test_temp_dir/later-trap-marker"
        lock_path="$test_temp_dir/backup locks/existing-exit.lock"
        if (
            trap 'test_later_exit_handler' EXIT
            backup_lock_acquire_path "$lock_path"
            LOCKFILE="$lock_path"
            export LOCKFILE
            backup_lock_install_traps
            phoenix_trap_dispatch EXIT
            trap - EXIT
            [ ! -e "$lock_path" ] && [ -f "$test_temp_dir/later-trap-marker" ]
        ); then
            test_pass "Existing EXIT handler is composed with lock cleanup"
        else
            test_fail "Lock registration overwrites an existing EXIT handler"
        fi

        lock_path="$test_temp_dir/backup locks/repeated-cleanup.lock"
        if (
            backup_lock_acquire_path "$lock_path"
            LOCKFILE="$lock_path"
            export LOCKFILE
            backup_lock_release "first cleanup"
            backup_lock_release "repeated cleanup"
            [ ! -e "$lock_path" ]
        ); then
            test_pass "Repeated owned-lock cleanup is harmless"
        else
            test_fail "Repeated owned-lock cleanup fails"
        fi

        lock_path="$test_temp_dir/backup locks/cleanup-diagnostic.lock"
        if backup_lock_acquire_path "$lock_path"; then
            lock_token="$BACKUP_LOCK_OWNER_TOKEN"
            if lock_cleanup_output=$(
                LOCKFILE="$lock_path"
                BACKUP_LOCK_OWNER_TOKEN="different-owner"
                backup_lock_release "fixture failure stage" 2>&1
            ); then
                test_fail "Mismatched-owner cleanup reports success"
            elif grep -Fq "Backup lock cleanup failed" <<< "$lock_cleanup_output" &&
                grep -Fq "Lock Path : $lock_path" <<< "$lock_cleanup_output" &&
                grep -Fq "Stage     : fixture failure stage" <<< "$lock_cleanup_output" &&
                grep -Fq "Reason    : owner token does not match" <<< "$lock_cleanup_output" &&
                [ -f "$lock_path" ]; then
                test_pass "Cleanup failure reports path, stage, and reason"
            else
                test_fail "Cleanup failure diagnostics are incomplete"
            fi
            backup_lock_cleanup_path "$lock_path" "$lock_token" || true
        else
            test_fail "Unable to prepare cleanup diagnostic fixture"
        fi


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

        verification_resolve_expected_services_mode "" "$test_temp_dir/recovery"
        if [ "$VERIFY_EXPECTED_SERVICES_MODE" = auto ] &&
            [ "$VERIFY_EXPECTED_EFFECTIVE_MODE" = advisory ]; then
            test_pass "Verify mode defaults to auto advisory for fixtures"
        else
            test_fail "Verify auto mode is incorrect for fixtures"
        fi
        verification_resolve_expected_services_mode invalid "$test_temp_dir/recovery"
        if [ "$VERIFY_EXPECTED_SERVICES_MODE" = auto ] &&
            [ "$VERIFY_EXPECTED_MODE_FALLBACK" = yes ]; then
            test_pass "Invalid verify mode falls back safely"
        else
            test_fail "Invalid verify mode does not fall back"
        fi
        verification_resolve_expected_services_mode auto /volume2/docker
        if [ "$VERIFY_EXPECTED_EFFECTIVE_MODE" = required ]; then
            test_pass "Auto mode requires services for volume2 Docker"
        else
            test_fail "Auto mode weakens real NAS service checks"
        fi

        verification_legacy_fixture="$test_temp_dir/verify legacy fixture"
        mkdir -p "$verification_legacy_fixture/backup/manifests/inventory/legacy-id"
        printf "service-one service-two\n" > \
            "$verification_legacy_fixture/backup/manifests/inventory/legacy-id/expected-services.txt"
        verification_resolve_expected_services_mode auto "$verification_legacy_fixture"
        if [ "$VERIFY_EXPECTED_EFFECTIVE_MODE" = advisory ]; then
            test_pass "Expected-services list alone remains advisory"
        else
            test_fail "Expected-services list alone incorrectly forces required mode"
        fi

        verification_resolve_expected_services_mode auto "/home/benja/fixture-restore"
        if [ "$VERIFY_EXPECTED_EFFECTIVE_MODE" = advisory ]; then
            test_pass "Home fixture targets default to advisory"
        else
            test_fail "Home fixture target is classified as production"
        fi

        verification_resolve_expected_services_mode auto /volume2/docker/service-one
        if [ "$VERIFY_EXPECTED_EFFECTIVE_MODE" = required ]; then
            test_pass "Normalised volume2 Docker descendants are required"
        else
            test_fail "Volume2 Docker descendant is not required"
        fi
        verification_resolve_expected_services_mode auto /volume2/docker-test
        if [ "$VERIFY_EXPECTED_EFFECTIVE_MODE" = advisory ]; then
            test_pass "Docker-like path names do not bypass path boundaries"
        else
            test_fail "Docker-test path is mistaken for volume2 Docker"
        fi
        verification_resolve_expected_services_mode auto /volume2/docker/../docker-test
        if [ "$VERIFY_EXPECTED_EFFECTIVE_MODE" = advisory ]; then
            test_pass "Path normalisation prevents production-path tricks"
        else
            test_fail "Unnormalised path trick forces required mode"
        fi

        verification_policy_fixture="$test_temp_dir/verify policy fixture"
        mkdir -p "$verification_policy_fixture/backup/manifests/inventory/policy-id"
        printf "original_source=/test/source\nexpected_services_policy=required\nproduction_docker_recovery=no\n" > \
            "$verification_policy_fixture/backup/manifests/inventory/policy-id/service-policy.txt"
        verification_resolve_expected_services_mode auto "$verification_policy_fixture"
        if [ "$VERIFY_EXPECTED_EFFECTIVE_MODE" = required ]; then
            test_pass "Explicit required inventory policy is honoured"
        else
            test_fail "Explicit required inventory policy is ignored"
        fi
        verification_resolve_expected_services_mode advisory "$verification_policy_fixture"
        if [ "$VERIFY_EXPECTED_EFFECTIVE_MODE" = advisory ]; then
            test_pass "Explicit advisory config overrides required metadata"
        else
            test_fail "Required metadata overrides advisory config"
        fi

        printf "original_source=/volume2/docker\nexpected_services_policy=advisory\nproduction_docker_recovery=yes\n" > \
            "$verification_policy_fixture/backup/manifests/inventory/policy-id/service-policy.txt"
        verification_resolve_expected_services_mode auto "$verification_policy_fixture"
        if [ "$VERIFY_EXPECTED_EFFECTIVE_MODE" = advisory ]; then
            test_pass "Explicit advisory inventory policy is honoured"
        else
            test_fail "Explicit advisory inventory policy is ignored"
        fi
        verification_resolve_expected_services_mode required "$verification_policy_fixture"
        if [ "$VERIFY_EXPECTED_EFFECTIVE_MODE" = required ]; then
            test_pass "Explicit config overrides advisory metadata"
        else
            test_fail "Metadata overrides explicit config"
        fi
        verification_resolve_expected_services_mode disabled "$verification_policy_fixture"
        if [ "$VERIFY_EXPECTED_EFFECTIVE_MODE" = disabled ]; then
            test_pass "Explicit disabled config overrides metadata"
        else
            test_fail "Metadata overrides disabled config"
        fi

        verification_source_fixture="$test_temp_dir/verify source fixture"
        mkdir -p "$verification_source_fixture/backup/manifests/inventory/source-id"
        printf "Project Phoenix Inventory\nSource: /volume2/docker/\n" > \
            "$verification_source_fixture/backup/manifests/inventory/source-id/summary.txt"
        verification_resolve_expected_services_mode auto "$verification_source_fixture"
        if [ "$VERIFY_EXPECTED_EFFECTIVE_MODE" = required ]; then
            test_pass "Production source metadata selects required mode"
        else
            test_fail "Production source metadata is not authoritative"
        fi
        printf "Project Phoenix Inventory\nSource: /mnt/c/Projects/ProjectPhoenix/test-local/core-stabilisation-source/\n" > \
            "$verification_source_fixture/backup/manifests/inventory/source-id/summary.txt"
        verification_resolve_expected_services_mode auto "$verification_source_fixture"
        if [ "$VERIFY_EXPECTED_EFFECTIVE_MODE" = advisory ]; then
            test_pass "Test source metadata selects advisory mode"
        else
            test_fail "Test source metadata is classified as production"
        fi

        verification_resolve_expected_services_mode auto relative-ambiguous-fixture
        if [ "$VERIFY_EXPECTED_EFFECTIVE_MODE" = advisory ]; then
            test_pass "Ambiguous auto classification defaults to advisory"
        else
            test_fail "Ambiguous auto classification defaults to required"
        fi
        if [ "$(service_policy_resolve_for_source auto \
            /mnt/c/Projects/ProjectPhoenix/test-local/core-stabilisation-source/)" = advisory ] &&
            [ "$(service_policy_resolve_for_source auto /volume2/docker/)" = required ]; then
            test_pass "Inventory policy classifies fixture and production sources correctly"
        else
            test_fail "Inventory source policy classification is incorrect"
        fi

        # shellcheck disable=SC2034 # Fixture consumed by verification_evaluate_status.
        VERIFY_FILES=1
        # shellcheck disable=SC2034 # Fixture consumed by verification_evaluate_status.
        VERIFY_UNREADABLE_FILES=0
        # shellcheck disable=SC2034 # Fixture consumed by verification_evaluate_status.
        VERIFY_UNREADABLE_DIRECTORIES=0
        VERIFY_BROKEN_SYMLINKS=0
        VERIFY_COMPOSE_FILES=1
        # shellcheck disable=SC2034 # Fixture consumed by verification_evaluate_status.
        VERIFY_INVENTORY="found"
        # shellcheck disable=SC2034 # Fixture consumed by verification_evaluate_status.
        VERIFY_MANIFEST="found"
        # shellcheck disable=SC2034 # Fixture consumed by verification_evaluate_status.
        VERIFY_RESTORE_GUIDE="found"
        VERIFY_EMPTY_TOP_LEVEL_DIRECTORIES=0
        VERIFY_EXPECTED_SKIPPED="no"
        VERIFY_EXPECTED_MISSING=1
        VERIFY_EXPECTED_EFFECTIVE_MODE=advisory
        if [ "$(verification_evaluate_status)" = WARNING ]; then
            test_pass "Fixture auto and advisory modes warn for missing services"
        else
            test_fail "Advisory expected services fail a fixture"
        fi
        VERIFY_EXPECTED_EFFECTIVE_MODE=required
        if verification_evaluate_status >/dev/null; then
            test_fail "Required expected services do not fail"
        else
            test_pass "Required expected services fail when missing"
        fi
        VERIFY_EXPECTED_EFFECTIVE_MODE=disabled
        verification_compare_expected_services "$test_temp_dir/recovery" "missing-service"
        if [ "$VERIFY_EXPECTED_SKIPPED" = yes ] &&
            [ "$(verification_evaluate_status)" = PASS ]; then
            test_pass "Disabled expected services are skipped clearly"
        else
            test_fail "Disabled expected services are still enforced"
        fi
        VERIFY_BROKEN_SYMLINKS=1
        verification_status="PASS"
        for service_mode in required advisory disabled; do
            VERIFY_EXPECTED_EFFECTIVE_MODE="$service_mode"
            if verification_evaluate_status >/dev/null; then
                verification_status="FAILED"
            fi
        done
        if [ "$verification_status" = "PASS" ]; then
            test_pass "Structural failures remain authoritative in every service mode"
        else
            test_fail "A service mode weakens structural failures"
        fi
        VERIFY_BROKEN_SYMLINKS=0

        metadata_inventory="$test_temp_dir/metadata inventory"
        metadata_guide="$test_temp_dir/restore guide.md"
        metadata_root="$test_temp_dir/fresh backup/backup"
        mkdir -p "$metadata_inventory"
        printf "inventory fixture\n" > "$metadata_inventory/summary.txt"
        printf "restore fixture\n" > "$metadata_guide"
        if backup_publish_metadata_local "$metadata_inventory" "$metadata_guide" \
            "$metadata_root" fixture-id &&
            [ -f "$metadata_root/restore/README.md" ] &&
            [ -f "$metadata_root/manifests/inventory/fixture-id/summary.txt" ]; then
            test_pass "Fresh backup publication includes guide and inventory"
        else
            test_fail "Fresh backup metadata publication is incomplete"
        fi
        if backup_publish_metadata_local "$metadata_inventory" "$metadata_guide" \
            "$metadata_root" fixture-id; then
            test_pass "Identical metadata publication is idempotent"
        else
            test_fail "Identical metadata publication fails"
        fi
        printf "conflict\n" > "$metadata_inventory/summary.txt"
        if backup_publish_metadata_local "$metadata_inventory" "$metadata_guide" \
            "$metadata_root" fixture-id; then
            test_fail "Conflicting timestamped inventory is overwritten"
        else
            test_pass "Conflicting timestamped inventory fails safely"
        fi
        if run_backup_metadata_hook 0 false; then
            test_fail "Metadata publication failure reports success"
        elif [ "$BACKUP_METADATA_STATUS" = failed ]; then
            test_pass "Metadata publication failure is reported accurately"
        else
            test_fail "Metadata publication failure status is unclear"
        fi
        backup_set_outcome_status 0 success failed
        if [ "$BACKUP_HISTORY_STATUS" = partial ] &&
            [[ "$BACKUP_HISTORY_DETAILS" == *"metadata publication failed"* ]]; then
            test_pass "Metadata failure prevents a full backup PASS"
        else
            test_fail "Metadata failure is lost from backup outcome"
        fi
        if integrity_remote_path_selected backup/restore/README.md &&
            integrity_remote_path_selected backup/manifests/inventory/fixture/summary.txt &&
            ! integrity_remote_path_selected backup/manifests/integrity/latest.txt; then
            test_pass "Integrity includes metadata and excludes its own directory"
        else
            test_fail "Integrity metadata selection is incorrect"
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

        integrity_fetch_root="$test_temp_dir/fetch project"
        integrity_remote_fixture="$test_temp_dir/remote-latest.txt"
        mkdir -p "$integrity_fetch_root/manifests"
        sed "/^# created_at=/a # reference_file=integrity-mocked.txt" \
            "$integrity_manifest_one" > "$integrity_remote_fixture"
        if integrity_fetch_with_downloader \
            "$integrity_fetch_root/manifests" "$integrity_fetch_root" \
            cp -- "$integrity_remote_fixture" &&
            [ -f "$integrity_fetch_root/manifests/integrity/remote/integrity-mocked.txt" ] &&
            [ -f "$integrity_fetch_root/manifests/integrity/remote/latest.txt" ] &&
            [ ! -L "$integrity_fetch_root/manifests/integrity/remote/latest.txt" ]; then
            test_pass "Mocked remote integrity fetch publishes validated copies"
        else
            test_fail "Mocked remote integrity fetch failed"
        fi

        if integrity_fetch_with_downloader \
            "$integrity_fetch_root/manifests" "$integrity_fetch_root" \
            cp -- "$integrity_remote_fixture"; then
            test_pass "Identical timestamped and latest repeated fetch succeeds"
        else
            test_fail "Identical repeated remote integrity fetch is not idempotent"
        fi

        printf "stale latest\n" > "$integrity_fetch_root/manifests/integrity/remote/latest.txt"
        if integrity_fetch_with_downloader             "$integrity_fetch_root/manifests" "$integrity_fetch_root"             cp -- "$integrity_remote_fixture" &&
            cmp -s -- "$integrity_remote_fixture"                 "$integrity_fetch_root/manifests/integrity/remote/latest.txt"; then
            test_pass "Differing local latest is replaced atomically"
        else
            test_fail "Differing local latest is not replaced safely"
        fi

        if integrity_fetch_with_downloader             "$integrity_fetch_root/manifests" "$integrity_fetch_root"             cp -- "$integrity_remote_fixture" &&
            [ -z "${INTEGRITY_FETCH_ERROR_STAGE:-}" ]; then
            test_pass "Successful publication does not report a partial failure"
        else
            test_fail "Safely published fetch reports a false failure"
        fi

        integrity_changed_fixture="$test_temp_dir/remote-latest-changed.txt"
        sed "s/# created_at=fixed-time/# created_at=changed-time/"             "$integrity_remote_fixture" > "$integrity_changed_fixture"
        integrity_collision_root="$test_temp_dir/fetch collision"
        mkdir -p "$integrity_collision_root/manifests"
        integrity_fetch_with_downloader             "$integrity_collision_root/manifests" "$integrity_collision_root"             cp -- "$integrity_remote_fixture"
        if integrity_fetch_with_downloader             "$integrity_collision_root/manifests" "$integrity_collision_root"             cp -- "$integrity_changed_fixture"; then
            test_fail "Different timestamped content overwrites an existing reference"
        elif cmp -s -- "$integrity_remote_fixture"             "$integrity_collision_root/manifests/integrity/remote/integrity-mocked.txt" &&
            [ "$INTEGRITY_FETCH_ERROR_STAGE" = "timestamp publication" ]; then
            test_pass "Different timestamped content fails without overwrite"
        else
            test_fail "Timestamp collision handling changed the protected reference"
        fi

        integrity_symlink_root="$test_temp_dir/fetch symlink"
        mkdir -p "$integrity_symlink_root/manifests/integrity/remote"
        ln -s "$integrity_remote_fixture"             "$integrity_symlink_root/manifests/integrity/remote/integrity-mocked.txt"
        if integrity_fetch_with_downloader             "$integrity_symlink_root/manifests" "$integrity_symlink_root"             cp -- "$integrity_remote_fixture"; then
            test_fail "Symlink timestamped target is accepted"
        elif [ -L "$integrity_symlink_root/manifests/integrity/remote/integrity-mocked.txt" ] &&
            [ "$INTEGRITY_FETCH_ERROR_STAGE" = "timestamp publication" ]; then
            test_pass "Symlink timestamped target fails safely"
        else
            test_fail "Symlink timestamped target handling is unsafe"
        fi

        if integrity_fetch_with_downloader             "$integrity_fetch_root/manifests" "$integrity_fetch_root"             false; then
            test_fail "Failed downloader is reported as success"
        elif [ "$INTEGRITY_FETCH_ERROR_STAGE" = "remote fetch" ]; then
            test_pass "Remote fetch failure identifies its stage"
        else
            test_fail "Remote fetch failure stage is unclear"
        fi

        if integrity_fetch_with_downloader \
            "$integrity_fetch_root/manifests" "$integrity_fetch_root" \
            cp -- "$test_temp_dir/malformed-integrity.txt"; then
            test_fail "Remote integrity fetch publishes malformed manifests"
        elif [ "$INTEGRITY_FETCH_ERROR_STAGE" = "manifest validation" ]; then
            test_pass "Remote integrity fetch rejects malformed manifests at validation"
        else
            test_fail "Malformed manifest failure stage is unclear"
        fi

        if integrity_manifest_root_safe "" "$integrity_fetch_root" ||
            integrity_manifest_root_safe / "$integrity_fetch_root" ||
            integrity_manifest_root_safe /integrity "$integrity_fetch_root" ||
            integrity_manifest_root_safe "$test_temp_dir/outside" "$integrity_fetch_root"; then
            test_fail "Remote integrity fetch accepts unsafe manifest roots"
        else
            test_pass "Remote integrity fetch rejects unsafe manifest roots"
        fi

        retention_resolve_count ""
        if [ "$RETENTION_COUNT" = "5" ] &&
            [ "$RETENTION_COUNT_DEFAULTED" = "yes" ]; then
            test_pass "Integrity retention defaults to five"
        else
            test_fail "Integrity retention default is incorrect"
        fi
        retention_resolve_count 3
        if [ "$RETENTION_COUNT" = "3" ] &&
            [ "$RETENTION_COUNT_DEFAULTED" = "no" ]; then
            test_pass "Integrity retention honours valid count"
        else
            test_fail "Integrity retention ignores valid count"
        fi
        retention_resolve_count invalid
        if [ "$RETENTION_COUNT" = "5" ] &&
            [ "$RETENTION_COUNT_DEFAULTED" = "yes" ]; then
            test_pass "Invalid integrity retention falls back safely"
        else
            test_fail "Invalid integrity retention does not fall back"
        fi

        retention_directory="$test_temp_dir/retention history with spaces"
        mkdir -p "$retention_directory"
        for retention_index in 1 2 3 4 5 6 7; do
            printf "manifest %s\n" "$retention_index" > \
                "$retention_directory/integrity-2026070${retention_index}-010000.txt"
        done
        cp -- "$retention_directory/integrity-20260707-010000.txt" \
            "$retention_directory/latest.txt"
        printf "ignored\n" > "$retention_directory/notes.txt"
        printf "suspicious\n" > "$retention_directory/integrity-bad.txt"
        retention_analyse_directory "$retention_directory" 5
        if [ "$RETENTION_TIMESTAMPED_COUNT" = "7" ] &&
            [ "$RETENTION_RETAINED" = "5" ] &&
            [ "$RETENTION_ELIGIBLE" = "2" ] &&
            [ "${RETENTION_ELIGIBLE_FILES[*]}" = \
                "integrity-20260701-010000.txt integrity-20260702-010000.txt" ] &&
            [ "$RETENTION_LATEST_STATUS" = "regular file" ] &&
            [ "$RETENTION_LATEST_MATCHES" = "yes" ] &&
            [ "$RETENTION_SUSPICIOUS_COUNT" = "1" ]; then
            test_pass "Integrity retention classifies history deterministically"
        else
            test_fail "Integrity retention history classification is incorrect"
        fi

        retention_mock_output=$(retention_emit_analysis)
        if retention_parse_analysis "$retention_mock_output" &&
            [ "$RETENTION_TIMESTAMPED_COUNT" = "7" ] &&
            [ "$RETENTION_ELIGIBLE" = "2" ]; then
            test_pass "Mocked remote retention output parses safely"
        else
            test_fail "Mocked remote retention output parsing failed"
        fi

        retention_mismatch_directory="$test_temp_dir/retention mismatch"
        mkdir -p "$retention_mismatch_directory"
        printf "newest\n" > \
            "$retention_mismatch_directory/integrity-20260713-010000.txt"
        printf "different\n" > "$retention_mismatch_directory/latest.txt"
        retention_analyse_directory "$retention_mismatch_directory" 5
        if [ "$RETENTION_LATEST_MATCHES" = "no" ]; then
            test_pass "Integrity retention detects mismatched latest"
        else
            test_fail "Integrity retention misses mismatched latest"
        fi

        retention_symlink_directory="$test_temp_dir/retention symlink"
        mkdir -p "$retention_symlink_directory"
        printf "manifest\n" > \
            "$retention_symlink_directory/integrity-20260713-020000.txt"
        ln -s "integrity-20260713-020000.txt" \
            "$retention_symlink_directory/latest.txt"
        retention_analyse_directory "$retention_symlink_directory" 5
        if [ "$RETENTION_LATEST_STATUS" = "symlink" ]; then
            test_pass "Integrity retention warns about symlink latest"
        else
            test_fail "Integrity retention misses symlink latest"
        fi

        if integrity_cleanup_confirmation_matches "DELETE OLD INTEGRITY MANIFESTS" &&
            ! integrity_cleanup_confirmation_matches "delete old integrity manifests"; then
            test_pass "Integrity cleanup requires exact confirmation"
        else
            test_fail "Integrity cleanup confirmation is not exact"
        fi

        cleanup_directory="$test_temp_dir/cleanup manifests"
        mkdir -p "$cleanup_directory"
        for retention_index in 1 2 3 4; do
            printf "cleanup %s\n" "$retention_index" > "$cleanup_directory/integrity-2026070${retention_index}-010000.txt"
        done
        cp -- "$cleanup_directory/integrity-20260704-010000.txt" "$cleanup_directory/latest.txt"
        printf "unrelated\n" > "$cleanup_directory/notes.txt"
        ln -s "integrity-20260704-010000.txt" "$cleanup_directory/integrity-20260101-000000.txt"
        retention_analyse_directory "$cleanup_directory" 2
        cleanup_expected=("${RETENTION_ELIGIBLE_FILES[@]}")
        if [ "${#cleanup_expected[@]}" -eq 2 ] &&
            retention_delete_local_eligible "$cleanup_directory" 2 cleanup_expected &&
            [ ! -e "$cleanup_directory/integrity-20260701-010000.txt" ] &&
            [ ! -e "$cleanup_directory/integrity-20260702-010000.txt" ] &&
            [ -f "$cleanup_directory/integrity-20260703-010000.txt" ] &&
            [ -f "$cleanup_directory/integrity-20260704-010000.txt" ] &&
            [ -f "$cleanup_directory/latest.txt" ] &&
            [ -L "$cleanup_directory/integrity-20260101-000000.txt" ] &&
            [ -f "$cleanup_directory/notes.txt" ]; then
            test_pass "Integrity cleanup removes only explicitly eligible regular files"
        else
            test_fail "Integrity cleanup did not protect retained or unrelated entries"
        fi

        retention_analyse_directory "$cleanup_directory" 5
        if [ "$RETENTION_ELIGIBLE" -eq 0 ]; then
            test_pass "Integrity cleanup detects nothing-to-do fixtures"
        else
            test_fail "Integrity cleanup incorrectly finds eligible files"
        fi

        cleanup_changed_directory="$test_temp_dir/cleanup changed"
        mkdir -p "$cleanup_changed_directory"
        for retention_index in 1 2 3; do
            printf "changed %s\n" "$retention_index" > "$cleanup_changed_directory/integrity-2026060${retention_index}-010000.txt"
        done
        retention_analyse_directory "$cleanup_changed_directory" 2
        # shellcheck disable=SC2034 # Consumed through a nameref by the cleanup helper.
        cleanup_changed_expected=("${RETENTION_ELIGIBLE_FILES[@]}")
        printf "new\n" > "$cleanup_changed_directory/integrity-20260713-010000.txt"
        if retention_delete_local_eligible "$cleanup_changed_directory" 2 cleanup_changed_expected; then
            test_fail "Integrity cleanup uses a stale eligible set"
        elif [ -f "$cleanup_changed_directory/integrity-20260601-010000.txt" ]; then
            test_pass "Integrity cleanup cancels when the eligible set changes"
        else
            test_fail "Integrity cleanup changed files after a race"
        fi

        cleanup_script=$(retention_remote_cleanup_script 2 \
            integrity-20260701-010000.txt integrity-20260702-010000.txt)
        if [[ "$cleanup_script" == *"integrity-20260701-010000.txt"* ]] &&
            [[ "$cleanup_script" == *"integrity-20260702-010000.txt"* ]] &&
            ! retention_remote_cleanup_script 2 "../latest.txt" >/dev/null 2>&1; then
            test_pass "Remote cleanup transports only validated explicit filenames"
        else
            test_fail "Remote cleanup accepts unsafe filenames"
        fi

        cleanup_result=$(integrity_cleanup_failure_status 0)
        if [ "$cleanup_result" = "FAILED" ] &&
            [ "$(integrity_cleanup_failure_status 1)" = "PARTIAL" ]; then
            test_pass "Integrity cleanup distinguishes failed and partial outcomes"
        else
            test_fail "Integrity cleanup failure status is incorrect"
        fi

        unset HEALTH_BACKUP_WARNING_HOURS HEALTH_INTEGRITY_WARNING_HOURS HEALTH_REMOTE_USAGE_WARNING_PERCENT
        health_resolve_thresholds
        if [ "$HEALTH_BACKUP_HOURS" = 48 ] && [ "$HEALTH_INTEGRITY_HOURS" = 48 ] &&
            [ "$HEALTH_USAGE_PERCENT" = 85 ]; then
            test_pass "Health defaults are applied"
        else
            test_fail "Health defaults are incorrect"
        fi

        # shellcheck disable=SC2034 # Fixtures consumed by health_resolve_thresholds.
        HEALTH_BACKUP_WARNING_HOURS=24
        HEALTH_INTEGRITY_WARNING_HOURS=36
        HEALTH_REMOTE_USAGE_WARNING_PERCENT=90
        health_resolve_thresholds
        if [ "$HEALTH_BACKUP_HOURS" = 24 ] && [ "$HEALTH_INTEGRITY_HOURS" = 36 ] &&
            [ "$HEALTH_USAGE_PERCENT" = 90 ]; then
            test_pass "Health valid thresholds are honoured"
        else
            test_fail "Health valid thresholds are ignored"
        fi

        # shellcheck disable=SC2034 # Fixtures consumed by health_resolve_thresholds.
        HEALTH_BACKUP_WARNING_HOURS=invalid
        # shellcheck disable=SC2034 # Fixture consumed by health_resolve_thresholds.
        HEALTH_INTEGRITY_WARNING_HOURS=0
        # shellcheck disable=SC2034 # Fixture consumed by health_resolve_thresholds.
        HEALTH_REMOTE_USAGE_WARNING_PERCENT=101
        health_resolve_thresholds
        if [ "$HEALTH_BACKUP_HOURS" = 48 ] && [ "$HEALTH_INTEGRITY_HOURS" = 48 ] &&
            [ "$HEALTH_USAGE_PERCENT" = 85 ]; then
            test_pass "Health invalid thresholds fall back safely"
        else
            test_fail "Health invalid thresholds are accepted"
        fi

        health_now=$(date -d "2026-07-13 12:00:00" +%s)
        if [ "$(health_age_hours "2026-07-13 11:00:00" "$health_now")" = 1 ] &&
            ! health_age_warns 1 48; then
            test_pass "Recent backup and integrity ages pass"
        else
            test_fail "Recent health ages warn incorrectly"
        fi
        if health_age_warns 49 48; then
            test_pass "Old backup and integrity ages warn"
        else
            test_fail "Old health ages do not warn"
        fi
        if health_usage_warns 85 85; then
            test_pass "High filesystem usage warns"
        else
            test_fail "High filesystem usage does not warn"
        fi

        health_remote_fixture="destination_exists=yes
destination_readable=yes
filesystem=/dev/mock
filesystem_total_kb=1000
filesystem_used_kb=850
filesystem_available_kb=150
filesystem_usage=85
backup_size=1G
top_level_entries=3
recovery_guide=yes
inventory=yes
integrity_directory=yes
integrity_newest=integrity-20260713-010000.txt
integrity_count=7
integrity_retained=5
integrity_eligible=2
integrity_suspicious=0
remote_latest_status=regular file
remote_latest_matches=yes"
        if health_parse_remote_analysis "$health_remote_fixture" &&
            [ "$HEALTH_REMOTE_ELIGIBLE" = 2 ]; then
            test_pass "Mocked health SSH output parses without contacting the Pi"
        else
            test_fail "Mocked health SSH output parsing failed"
        fi

        if ! health_remote_checks_pass no yes yes; then
            test_pass "Health classifies SSH failure as failed"
        else
            test_fail "Health accepts an SSH failure"
        fi
        if ! health_remote_checks_pass yes no no; then
            test_pass "Health classifies a missing destination as failed"
        else
            test_fail "Health accepts a missing destination"
        fi
        if health_latest_mismatch_warns no yes yes; then
            test_pass "Health latest mismatch warns"
        else
            test_fail "Health latest mismatch does not warn"
        fi
        if health_retention_warns 2; then
            test_pass "Health retention eligibility warns"
        else
            test_fail "Health retention eligibility does not warn"
        fi
        if ! health_required_flags_pass yes yes no yes; then
            test_pass "Health fails when a required restore command is missing"
        else
            test_fail "Health accepts a missing restore command"
        fi
        if health_source_path_safe "$test_temp_dir/source path with spaces"; then
            test_pass "Health path checks support spaces"
        else
            test_fail "Health path checks reject spaces"
        fi

        inventory_source="$test_temp_dir/inventory source"
        mkdir -p "$inventory_source/service one" "$inventory_source/service two"
        printf "services:\n" > "$inventory_source/service one/compose.yml"
        printf "services:\n" > "$inventory_source/service two/docker-compose.yaml"

        if (
            SOURCE="$inventory_source"
            INVENTORY_DIR="$test_temp_dir/inventory docker absent"
            VERSION="test"
            BACKUP_HOST="mock-host"
            DESTINATION="/mock-destination"
            # shellcheck disable=SC2034 # Fixture consumed by generate_backup_inventory.
            EXPECTED_SERVICES="service one service two"
            generate_backup_inventory project-phoenix-docker-not-installed >/dev/null &&
                [ "$BACKUP_FILESYSTEM_INVENTORY_STATUS" = "success" ] &&
                [ "$BACKUP_DOCKER_INVENTORY_STATUS" = "unavailable" ] &&
                [ "$BACKUP_INVENTORY_STATUS" = "warning" ]
        ); then
            test_pass "Docker absence preserves successful filesystem inventory"
        else
            test_fail "Docker absence fails filesystem inventory"
        fi

        if grep -Fxq "Docker CLI unavailable" \
            "$test_temp_dir/inventory docker absent/containers.txt" &&
            grep -Fxq "Docker CLI unavailable" \
            "$test_temp_dir/inventory docker absent/docker-info.txt"; then
            test_pass "Docker absence creates clear runtime placeholders"
        else
            test_fail "Docker absence runtime placeholders are unclear"
        fi

        if (
            SOURCE="$inventory_source"
            INVENTORY_DIR="$test_temp_dir/inventory metadata allowed"
            VERSION="test"
            BACKUP_HOST="mock-host"
            DESTINATION="/mock-destination"
            generate_backup_inventory project-phoenix-docker-not-installed >/dev/null &&
                run_backup_metadata_hook 0 true &&
                [ "$BACKUP_METADATA_STATUS" = "success" ]
        ); then
            test_pass "Docker unavailability does not block metadata publication"
        else
            test_fail "Docker unavailability blocks metadata publication"
        fi

        if (
            SOURCE="$inventory_source"
            INVENTORY_DIR="$test_temp_dir/inventory docker warning"
            VERSION="test"
            BACKUP_HOST="mock-host"
            DESTINATION="/mock-destination"
            generate_backup_inventory false >/dev/null &&
                [ "$BACKUP_FILESYSTEM_INVENTORY_STATUS" = "success" ] &&
                [ "$BACKUP_DOCKER_INVENTORY_STATUS" = "warning" ] &&
                [ "$BACKUP_INVENTORY_STATUS" = "warning" ]
        ); then
            test_pass "Docker command failures are optional inventory warnings"
        else
            test_fail "Docker command failure incorrectly fails inventory"
        fi

        if (
            SOURCE="$inventory_source"
            INVENTORY_DIR="$test_temp_dir/inventory compose failure"
            VERSION="test"
            BACKUP_HOST="mock-host"
            DESTINATION="/mock-destination"
            ! generate_backup_inventory project-phoenix-docker-not-installed false \
                backup_inventory_source_sizes >/dev/null &&
                [ "$BACKUP_FILESYSTEM_INVENTORY_STATUS" = "failed" ] &&
                [ "$BACKUP_FILESYSTEM_INVENTORY_FAILURE" = "Compose-file discovery" ] &&
                [ "$BACKUP_INVENTORY_STATUS" = "failed" ]
        ); then
            test_pass "Compose discovery failure fails required inventory accurately"
        else
            test_fail "Compose discovery failure is not handled accurately"
        fi

        if (
            # shellcheck disable=SC2034 # Fixture consumed by inventory helpers.
            SOURCE="$inventory_source"
            # shellcheck disable=SC2034 # Fixture consumed by inventory helpers.
            INVENTORY_DIR="$test_temp_dir/inventory size failure"
            # shellcheck disable=SC2034 # Fixture consumed by inventory helpers.
            VERSION="test"
            # shellcheck disable=SC2034 # Fixture consumed by inventory helpers.
            BACKUP_HOST="mock-host"
            # shellcheck disable=SC2034 # Fixture consumed by inventory helpers.
            DESTINATION="/mock-destination"
            ! generate_backup_inventory project-phoenix-docker-not-installed \
                backup_inventory_compose_files false >/dev/null &&
                [ "$BACKUP_FILESYSTEM_INVENTORY_STATUS" = "failed" ] &&
                [ "$BACKUP_FILESYSTEM_INVENTORY_FAILURE" = "source-size collection" ]
        ); then
            test_pass "Source-size failure fails required inventory accurately"
        else
            test_fail "Source-size failure is not handled accurately"
        fi

        inventory_report=$(
            BACKUP_FILESYSTEM_INVENTORY_STATUS="failed"
            BACKUP_FILESYSTEM_INVENTORY_FAILURE="Compose-file discovery"
            BACKUP_DOCKER_INVENTORY_STATUS="unavailable"
            BACKUP_METADATA_STATUS="skipped"
            backup_report_inventory_status 2>&1
        )
        if grep -Fq "Filesystem Inventory FAIL: Compose-file discovery" <<< "$inventory_report" &&
            grep -Fq "Metadata publication skipped" <<< "$inventory_report" &&
            ! grep -Fq "Filesystem Inventory PASS" <<< "$inventory_report"; then
            test_pass "Backup summary reports required inventory status, not directory existence"
        else
            test_fail "Backup summary falsely passes a failed filesystem inventory"
        fi

        if (
            BACKUP_DOCKER_INVENTORY_STATUS="unavailable"
            backup_set_outcome_status 0 success success
            [ "$BACKUP_HISTORY_STATUS" = "completed" ]
        ); then
            test_pass "Clean payload with filesystem inventory and no Docker completes"
        else
            test_fail "Optional Docker absence degrades a clean backup outcome"
        fi

        if grep -Fq "Filesystem Inventory Status: success" \
            "$test_temp_dir/inventory docker absent/summary.txt" &&
            grep -Fq "Docker Runtime Inventory Status: unavailable" \
            "$test_temp_dir/inventory docker absent/summary.txt" &&
            grep -Fq "Docker CLI Found: no" \
            "$test_temp_dir/inventory docker absent/summary.txt" &&
            grep -Fq "Docker Daemon Reachable: not applicable" \
            "$test_temp_dir/inventory docker absent/summary.txt" &&
            grep -Fq "Overall Inventory Status: warning" \
            "$test_temp_dir/inventory docker absent/summary.txt" &&
            grep -Fq "Expected Services Policy: advisory" \
            "$test_temp_dir/inventory docker absent/summary.txt" &&
            grep -Fq "Production Docker Recovery: no" \
            "$test_temp_dir/inventory docker absent/summary.txt" &&
            grep -Fq "expected_services_policy=advisory" \
            "$test_temp_dir/inventory docker absent/service-policy.txt"; then
            test_pass "Published inventory summary includes runtime status metadata"
        else
            test_fail "Published inventory summary omits runtime status metadata"
        fi

        mkdir -p "$test_temp_dir/inventory production policy"
        if (
            SOURCE="/volume2/docker/"
            INVENTORY_DIR="$test_temp_dir/inventory production policy"
            export SOURCE INVENTORY_DIR
            backup_write_service_policy_metadata &&
                grep -Fxq "expected_services_policy=required" \
                    "$INVENTORY_DIR/service-policy.txt" &&
                grep -Fxq "production_docker_recovery=yes" \
                    "$INVENTORY_DIR/service-policy.txt"
        ); then
            test_pass "Production Docker inventory publishes required policy"
        else
            test_fail "Production Docker inventory policy is not required"
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
