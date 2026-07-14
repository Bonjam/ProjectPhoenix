#!/bin/bash

validate_config() {
    load_config || return 1
    VALIDATION_FAILED=0
    section "PROJECT PHOENIX CONFIG VALIDATION"

    check_required() {
        local name="$1" value="$2"
        if transport_config_value_present "$value"; then
            log_success "$name is set"
        else
            log_error "$name is missing or unsafe"
            VALIDATION_FAILED=1
        fi
    }

    check_required "PROJECT_NAME" "${PROJECT_NAME:-}"
    check_required "TAGLINE" "${TAGLINE:-}"
    check_required "SOURCE" "${SOURCE:-}"
    check_required "BACKUP_DIR" "${BACKUP_DIR:-}"

    if destination_id_valid "${DESTINATION_ID:-}"; then
        log_success "DESTINATION_ID is valid"
    else
        log_error "DESTINATION_ID is invalid"
        VALIDATION_FAILED=1
    fi
    if destination_transport_supported "${DESTINATION_TRANSPORT:-}"; then
        log_success "DESTINATION_TRANSPORT is supported"
    else
        log_error "DESTINATION_TRANSPORT is unsupported"
        VALIDATION_FAILED=1
    fi
    if transport_call validate_config; then
        log_success "$DESTINATION_TRANSPORT destination settings are valid"
    else
        log_error "$DESTINATION_TRANSPORT destination settings are invalid${LOCAL_PATH_ERROR:+: $LOCAL_PATH_ERROR}"
        VALIDATION_FAILED=1
    fi

    echo
    if [ "$VALIDATION_FAILED" -eq 0 ]; then
        log_success "Configuration is valid"
        return 0
    fi
    log_error "Configuration needs attention"
    return 1
}
