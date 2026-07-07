#!/bin/bash

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

    [ -f "$PROJECT_ROOT/VERSION" ] && doctor_pass "VERSION file exists" || doctor_fail "VERSION file missing"
    [ -f "$PROJECT_ROOT/scripts/phoenix.sh" ] && doctor_pass "Launcher exists" || doctor_fail "Launcher missing"
    [ -f "$PROJECT_ROOT/lib/core.sh" ] && doctor_pass "Core module exists" || doctor_fail "Core module missing"
    [ -f "$PROJECT_ROOT/lib/module-loader.sh" ] && doctor_pass "Module loader exists" || doctor_fail "Module loader missing"
    [ -f "$PROJECT_ROOT/lib/banner.sh" ] && doctor_pass "Banner module exists" || doctor_fail "Banner module missing"
    [ -f "$PROJECT_ROOT/lib/config.sh" ] && doctor_pass "Config module exists" || doctor_fail "Config module missing"
    [ -f "$PROJECT_ROOT/lib/logging.sh" ] && doctor_pass "Logging module exists" || doctor_fail "Logging module missing"
    [ -f "$PROJECT_ROOT/lib/backup.sh" ] && doctor_pass "Backup module exists" || doctor_fail "Backup module missing"
    [ -f "$PROJECT_ROOT/lib/restore.sh" ] && doctor_pass "Restore module exists" || doctor_fail "Restore module missing"
    [ -f "$PROJECT_ROOT/lib/discovery.sh" ] && doctor_pass "Discovery module exists" || doctor_fail "Discovery module missing"

    echo
    section "DOCUMENTATION CHECKS"

    [ -f "$PROJECT_ROOT/README.md" ] && doctor_pass "README exists" || doctor_fail "README missing"
    [ -f "$PROJECT_ROOT/SECURITY.md" ] && doctor_pass "SECURITY guide exists" || doctor_warn "SECURITY guide missing"
    [ -f "$PROJECT_ROOT/CONTRIBUTING.md" ] && doctor_pass "CONTRIBUTING guide exists" || doctor_warn "CONTRIBUTING guide missing"
    [ -f "$PROJECT_ROOT/docs/INSTALL.md" ] && doctor_pass "INSTALL guide exists" || doctor_warn "INSTALL guide missing"
    [ -f "$PROJECT_ROOT/docs/ROADMAP.md" ] && doctor_pass "ROADMAP exists" || doctor_warn "ROADMAP missing"

    echo
    section "CONFIGURATION CHECKS"

    CONFIG_FILE="$PROJECT_ROOT/config.conf"

    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"

        doctor_pass "config.conf exists"

        [ -n "${PROJECT_NAME:-}" ] && doctor_pass "PROJECT_NAME set" || doctor_fail "PROJECT_NAME missing"
        [ -n "${SOURCE:-}" ] && doctor_pass "SOURCE set" || doctor_fail "SOURCE missing"
        [ -n "${DESTINATION:-}" ] && doctor_pass "DESTINATION set" || doctor_fail "DESTINATION missing"
        [ -n "${BACKUP_HOST:-}" ] && doctor_pass "BACKUP_HOST set" || doctor_fail "BACKUP_HOST missing"
        [ -n "${BACKUP_USER:-}" ] && doctor_pass "BACKUP_USER set" || doctor_fail "BACKUP_USER missing"
        [ -n "${SSH_KEY:-}" ] && doctor_pass "SSH_KEY set" || doctor_fail "SSH_KEY missing"
        [ -n "${EXCLUDE_FILE:-}" ] && doctor_pass "EXCLUDE_FILE set" || doctor_warn "EXCLUDE_FILE missing"

        echo
        section "SOURCE CHECKS"

        if [ -d "$SOURCE" ]; then
            doctor_pass "Source folder exists"
        else
            doctor_warn "Source folder not found on this machine"
        fi
    else
        doctor_warn "config.conf not found"
        echo
        echo "Create one with:"
        echo
        echo "cp examples/config.example.conf config.conf"
        echo
        echo "Then edit config.conf for your system."
    fi

    echo
    section "REQUIREMENT CHECKS"

    command -v bash >/dev/null 2>&1 && doctor_pass "bash found" || doctor_fail "bash missing"
    command -v ssh >/dev/null 2>&1 && doctor_pass "ssh found" || doctor_fail "ssh missing"
    command -v rsync >/dev/null 2>&1 && doctor_pass "rsync found" || doctor_fail "rsync missing"

    if command -v docker >/dev/null 2>&1; then
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