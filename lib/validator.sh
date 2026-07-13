#!/bin/bash

validate_config() {
    load_config

    VALIDATION_FAILED=0

    section "PROJECT PHOENIX CONFIG VALIDATION"

    check_required() {
        local name="$1"
        local value="$2"

        if [ -n "$value" ]; then
            log_success "$name is set"
        else
            log_error "$name is missing"
            VALIDATION_FAILED=1
        fi
    }

    check_required "PROJECT_NAME" "${PROJECT_NAME:-}"
    check_required "TAGLINE" "${TAGLINE:-}"
    check_required "SOURCE" "${SOURCE:-}"
    check_required "DESTINATION" "${DESTINATION:-}"
    check_required "BACKUP_HOST" "${BACKUP_HOST:-}"
    check_required "BACKUP_USER" "${BACKUP_USER:-}"
    check_required "SSH_KEY" "${SSH_KEY:-}"
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

    echo

    if [ "$VALIDATION_FAILED" -eq 0 ]; then
        log_success "Configuration is valid"
        return 0
    else
        log_error "Configuration needs attention"
        return 1
    fi
}
