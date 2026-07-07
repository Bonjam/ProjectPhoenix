#!/bin/bash

check_requirements() {
    section "PROJECT PHOENIX REQUIREMENTS"

    REQUIRED_OK=0
    REQUIRED_FAIL=0

    check_required_command() {
        local command_name="$1"

        if command -v "$command_name" >/dev/null 2>&1; then
            log_success "$command_name found"
            REQUIRED_OK=$((REQUIRED_OK + 1))
        else
            log_error "$command_name missing"
            REQUIRED_FAIL=$((REQUIRED_FAIL + 1))
        fi
    }

    check_optional_command() {
        local command_name="$1"

        if command -v "$command_name" >/dev/null 2>&1; then
            log_success "$command_name found"
        else
            log_warning "$command_name not found optional"
        fi
    }

    echo "Required:"
    check_required_command "bash"
    check_required_command "ssh"
    check_required_command "rsync"
    check_required_command "find"
    check_required_command "du"

    echo
    echo "Optional:"
    check_optional_command "docker"
    check_optional_command "awk"
    check_optional_command "grep"

    echo
    echo "Required Passed : $REQUIRED_OK"
    echo "Required Failed : $REQUIRED_FAIL"

    echo

    if [ "$REQUIRED_FAIL" -eq 0 ]; then
        echo "PROJECT PHOENIX REQUIREMENTS: PASS"
        return 0
    else
        echo "PROJECT PHOENIX REQUIREMENTS: FAIL"
        return 1
    fi
}