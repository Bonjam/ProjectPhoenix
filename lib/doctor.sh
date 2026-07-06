#!/bin/bash

run_doctor() {
    load_config
    get_version

    section "PROJECT PHOENIX DOCTOR"

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

    echo "Version     : $VERSION"
    echo "Project     : $PROJECT_NAME"
    echo "Source      : $SOURCE"
    echo "Destination : ${BACKUP_USER}@${BACKUP_HOST}:${DESTINATION}"
    echo

    section "SYSTEM CHECKS"

    [ -f "$PROJECT_ROOT/VERSION" ] && doctor_pass "VERSION file exists" || doctor_fail "VERSION file missing"
    [ -f "$PROJECT_ROOT/lib/banner.sh" ] && doctor_pass "Banner module exists" || doctor_fail "Banner module missing"
    [ -f "$PROJECT_ROOT/lib/config.sh" ] && doctor_pass "Config module exists" || doctor_fail "Config module missing"
    [ -f "$PROJECT_ROOT/lib/logging.sh" ] && doctor_pass "Logging module exists" || doctor_fail "Logging module missing"
    [ -f "$PROJECT_ROOT/lib/inventory.sh" ] && doctor_pass "Inventory module exists" || doctor_fail "Inventory module missing"
    [ -f "$PROJECT_ROOT/lib/status.sh" ] && doctor_pass "Status module exists" || doctor_fail "Status module missing"
    [ -f "$PROJECT_ROOT/lib/backup.sh" ] && doctor_pass "Backup module exists" || doctor_fail "Backup module missing"

    echo
    section "CONFIGURATION CHECKS"

    [ -n "${PROJECT_NAME:-}" ] && doctor_pass "PROJECT_NAME set" || doctor_fail "PROJECT_NAME missing"
    [ -n "${SOURCE:-}" ] && doctor_pass "SOURCE set" || doctor_fail "SOURCE missing"
    [ -n "${DESTINATION:-}" ] && doctor_pass "DESTINATION set" || doctor_fail "DESTINATION missing"
    [ -n "${BACKUP_HOST:-}" ] && doctor_pass "BACKUP_HOST set" || doctor_fail "BACKUP_HOST missing"
    [ -n "${BACKUP_USER:-}" ] && doctor_pass "BACKUP_USER set" || doctor_fail "BACKUP_USER missing"
    [ -n "${SSH_KEY:-}" ] && doctor_pass "SSH_KEY set" || doctor_fail "SSH_KEY missing"

    echo
    section "SOURCE CHECKS"

    if [ -d "$SOURCE" ]; then
        doctor_pass "Source folder exists"
    else
        doctor_warn "Source folder not found on this machine"
    fi

    echo
    section "SUMMARY"

    echo "Passed : $CHECKS_PASSED"
    echo "Warned : $CHECKS_WARNED"
    echo "Failed : $CHECKS_FAILED"
    echo

    if [ "$CHECKS_FAILED" -eq 0 ]; then
        echo "PROJECT PHOENIX STATUS: READY"
    else
        echo "PROJECT PHOENIX STATUS: NEEDS ATTENTION"
    fi
}