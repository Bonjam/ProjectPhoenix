#!/bin/bash

check_requirements() {
    local transport="ssh-rsync"
    section "PROJECT PHOENIX REQUIREMENTS"
    REQUIRED_OK=0
    REQUIRED_FAIL=0

    check_required_command() {
        local command_name="$1"
        if discovery_has_command "$command_name"; then
            log_success "$command_name found"
            REQUIRED_OK=$((REQUIRED_OK + 1))
        else
            log_error "$command_name missing"
            REQUIRED_FAIL=$((REQUIRED_FAIL + 1))
        fi
    }
    check_optional_command() {
        local command_name="$1"
        if discovery_has_command "$command_name"; then log_success "$command_name found"; else log_warning "$command_name not found optional"; fi
    }

    if load_config_if_exists; then
        transport="$DESTINATION_TRANSPORT"
    else
        log_warning "config.conf not found; checking legacy ssh-rsync requirements"
    fi
    printf "Transport: %s\n\n" "$transport"
    echo "Required:"
    check_required_command bash
    check_required_command rsync
    check_required_command find
    check_required_command du
    if [ "$transport" = ssh-rsync ]; then
        check_required_command ssh
    elif [ "$transport" = local ]; then
        if transport_local_validate_config; then
            log_success "local destination path is safe"
            REQUIRED_OK=$((REQUIRED_OK + 1))
        else
            log_error "local destination path is unsafe: ${LOCAL_PATH_ERROR:-validation failed}"
            REQUIRED_FAIL=$((REQUIRED_FAIL + 1))
        fi
        if [ -d "$(dirname -- "$DESTINATION_PATH")" ] &&
            [ -r "$(dirname -- "$DESTINATION_PATH")" ] &&
            [ -x "$(dirname -- "$DESTINATION_PATH")" ]; then
            log_success "local destination parent exists"
            REQUIRED_OK=$((REQUIRED_OK + 1))
        else
            log_error "local destination parent is missing"
            REQUIRED_FAIL=$((REQUIRED_FAIL + 1))
        fi
    fi

    echo
    echo "Optional:"
    check_optional_command docker
    check_optional_command awk
    check_optional_command grep
    echo
    echo "Required Passed : $REQUIRED_OK"
    echo "Required Failed : $REQUIRED_FAIL"
    echo
    if [ "$REQUIRED_FAIL" -eq 0 ]; then echo "PROJECT PHOENIX REQUIREMENTS: PASS"; return 0; fi
    echo "PROJECT PHOENIX REQUIREMENTS: FAIL"
    return 1
}
