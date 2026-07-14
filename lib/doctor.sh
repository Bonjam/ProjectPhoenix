#!/bin/bash

doctor_check_file() {
    local path="$1"
    local pass_message="$2"
    local fail_message="$3"

    if [ -f "$path" ]; then
        doctor_pass "$pass_message"
    else
        doctor_fail "$fail_message"
    fi
}

doctor_check_file_warn() {
    local path="$1"
    local pass_message="$2"
    local warn_message="$3"

    if [ -f "$path" ]; then
        doctor_pass "$pass_message"
    else
        doctor_warn "$warn_message"
    fi
}

doctor_check_variable() {
    local value="$1"
    local pass_message="$2"
    local fail_message="$3"

    if [ -n "$value" ]; then
        doctor_pass "$pass_message"
    else
        doctor_fail "$fail_message"
    fi
}

doctor_check_variable_warn() {
    local value="$1"
    local pass_message="$2"
    local warn_message="$3"

    if [ -n "$value" ]; then
        doctor_pass "$pass_message"
    else
        doctor_warn "$warn_message"
    fi
}

doctor_check_command() {
    local command_name="$1"
    local pass_message="$2"
    local fail_message="$3"

    if discovery_has_command "$command_name"; then
        doctor_pass "$pass_message"
    else
        doctor_fail "$fail_message"
    fi
}

run_doctor() {
    get_version

    CHECKS_PASSED=0
    CHECKS_FAILED=0
    CHECKS_WARNED=0

    doctor_pass() {
        log_success "$1"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    }

    doctor_fail() {
        log_error "$1"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
    }

    doctor_warn() {
        log_warning "$1"
        CHECKS_WARNED=$((CHECKS_WARNED + 1))
    }

    section "PROJECT PHOENIX DOCTOR"

    echo "Version     : $VERSION"
    echo "Project     : $PROJECT_NAME"
    echo "Root        : $PROJECT_ROOT"
    echo

    section "SYSTEM CHECKS"

    doctor_check_file "$PROJECT_ROOT/VERSION" "VERSION file exists" "VERSION file missing"
    doctor_check_file "$PROJECT_ROOT/scripts/phoenix.sh" "Launcher exists" "Launcher missing"
    doctor_check_file "$PROJECT_ROOT/lib/core.sh" "Core module exists" "Core module missing"
    doctor_check_file "$PROJECT_ROOT/lib/module-loader.sh" "Module loader exists" "Module loader missing"
    doctor_check_file "$PROJECT_ROOT/lib/banner.sh" "Banner module exists" "Banner module missing"
    doctor_check_file "$PROJECT_ROOT/lib/config.sh" "Config module exists" "Config module missing"
    doctor_check_file "$PROJECT_ROOT/lib/logging.sh" "Logging module exists" "Logging module missing"
    doctor_check_file "$PROJECT_ROOT/lib/backup.sh" "Backup module exists" "Backup module missing"
    doctor_check_file "$PROJECT_ROOT/lib/restore.sh" "Restore module exists" "Restore module missing"
    doctor_check_file "$PROJECT_ROOT/lib/discovery.sh" "Discovery module exists" "Discovery module missing"
    doctor_check_file "$PROJECT_ROOT/lib/transports/common.sh" "Transport registry exists" "Transport registry missing"
    doctor_check_file "$PROJECT_ROOT/lib/transports/ssh-rsync.sh" "ssh-rsync provider exists" "ssh-rsync provider missing"
    doctor_check_file "$PROJECT_ROOT/lib/transports/local.sh" "Local provider exists" "Local provider missing"

    echo
    section "DOCUMENTATION CHECKS"

    doctor_check_file "$PROJECT_ROOT/README.md" "README exists" "README missing"
    doctor_check_file_warn "$PROJECT_ROOT/SECURITY.md" "SECURITY guide exists" "SECURITY guide missing"
    doctor_check_file_warn "$PROJECT_ROOT/CONTRIBUTING.md" "CONTRIBUTING guide exists" "CONTRIBUTING guide missing"
    doctor_check_file_warn "$PROJECT_ROOT/docs/INSTALL.md" "INSTALL guide exists" "INSTALL guide missing"
    doctor_check_file_warn "$PROJECT_ROOT/docs/ROADMAP.md" "ROADMAP exists" "ROADMAP missing"

    echo
    section "CONFIGURATION CHECKS"

    if load_config_if_exists; then
        doctor_pass "config.conf exists"
        doctor_check_variable "${PROJECT_NAME:-}" "PROJECT_NAME set" "PROJECT_NAME missing"
        doctor_check_variable "${SOURCE:-}" "SOURCE set" "SOURCE missing"
        doctor_check_variable_warn "${EXCLUDE_FILE:-}" "EXCLUDE_FILE set" "EXCLUDE_FILE missing"
        if transport_call validate_config; then
            doctor_pass "$DESTINATION_TRANSPORT destination settings valid"
        else
            doctor_fail "$DESTINATION_TRANSPORT destination settings invalid${LOCAL_PATH_ERROR:+: $LOCAL_PATH_ERROR}"
        fi
        if [ "$DESTINATION_TRANSPORT" = local ]; then
            if [ -d "$(dirname -- "$DESTINATION_PATH")" ] &&
                [ -r "$(dirname -- "$DESTINATION_PATH")" ] &&
                [ -x "$(dirname -- "$DESTINATION_PATH")" ]; then
                doctor_pass "Local destination parent exists"
            else
                doctor_fail "Local destination parent is missing"
            fi
        else
            doctor_check_variable "${BACKUP_HOST:-}" "BACKUP_HOST set" "BACKUP_HOST missing"
            doctor_check_variable "${BACKUP_USER:-}" "BACKUP_USER set" "BACKUP_USER missing"
            doctor_check_variable "${SSH_KEY:-}" "SSH_KEY set" "SSH_KEY missing"
        fi
        echo
        section "SOURCE CHECKS"
        if [ -d "$SOURCE" ]; then doctor_pass "Source folder exists"; else doctor_warn "Source folder not found on this machine"; fi
    else
        doctor_warn "config.conf not found"
        echo
        echo "Create one with:"
        echo "cp examples/config.example.conf config.conf"
    fi

    echo
    section "REQUIREMENT CHECKS"

    doctor_check_command "bash" "bash found" "bash missing"
    if [ "${DESTINATION_TRANSPORT:-ssh-rsync}" = ssh-rsync ]; then
        doctor_check_command "ssh" "ssh found" "ssh missing"
    fi
    doctor_check_command "rsync" "rsync found" "rsync missing"

    if discovery_has_docker; then
        doctor_pass "docker found optional"
    else
        doctor_warn "docker not found optional"
    fi

    echo
    section "SUMMARY"

    echo "Passed : $CHECKS_PASSED"
    echo "Warned : $CHECKS_WARNED"
    echo "Failed : $CHECKS_FAILED"
    echo

    if [ "$CHECKS_FAILED" -eq 0 ]; then
        echo "PROJECT PHOENIX STATUS: READY"
        return 0
    else
        echo "PROJECT PHOENIX STATUS: NEEDS ATTENTION"
        return 1
    fi
}
