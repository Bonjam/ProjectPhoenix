#!/bin/bash

source_error() {
    if declare -F log_error >/dev/null 2>&1; then
        log_error "$1"
    else
        printf 'ERROR: %s\n' "$1" >&2
    fi
}

source_resolve_context() {
    if [ "${SOURCE_CONTEXT_RESOLVED:-no}" = yes ]; then
        return 0
    fi

    if [ -z "${SOURCE_TRANSPORT+x}" ]; then
        SOURCE_LEGACY_CONFIGURATION=yes
    else
        SOURCE_LEGACY_CONFIGURATION=no
    fi

    SOURCE_TRANSPORT="${SOURCE_TRANSPORT:-local}"

    if ! source_registered "$SOURCE_TRANSPORT"; then
        source_error "Unsupported SOURCE_TRANSPORT: $SOURCE_TRANSPORT (supported: local, ssh)"
        return 1
    fi

    source_call configure || {
        source_error "Source configuration could not be resolved"
        return 1
    }

    SOURCE_CONTEXT_RESOLVED=yes
}

source_summary() {
    source_call summary
}

run_source_info() {
    load_config || return 1

    if ! source_call validate_config; then
        source_error "Source settings are invalid"
        return 1
    fi

    section "PROJECT PHOENIX SOURCE"
    printf "%-22s: %s\n" "Transport" "$SOURCE_TRANSPORT"
    source_call info
    printf "%-22s: %s\n" "Legacy Configuration" "$SOURCE_LEGACY_CONFIGURATION"
    echo
    echo "No connection test was performed."
    echo "No files were changed."
}

run_source_check() {
    load_config || return 1

    section "PROJECT PHOENIX SOURCE CHECK"
    printf "%-24s: %s\n" "Transport" "$SOURCE_TRANSPORT"

    source_call check
}
