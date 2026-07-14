#!/bin/bash

declare -gA PHOENIX_SOURCE_PROVIDERS=()

source_register() {
    local provider="$1" prefix="$2"

    [[ "$provider" =~ ^[a-z0-9][a-z0-9-]*$ ]] || return 1
    [[ "$prefix" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1

    [ -z "${PHOENIX_SOURCE_PROVIDERS[$provider]:-}" ] ||
        [ "${PHOENIX_SOURCE_PROVIDERS[$provider]}" = "$prefix" ] ||
        return 1

    PHOENIX_SOURCE_PROVIDERS["$provider"]="$prefix"
}

source_registered() {
    local provider="${1:-}"
    [ -n "$provider" ] || return 1
    [ -n "${PHOENIX_SOURCE_PROVIDERS[$provider]:-}" ]
}

source_operation_function() {
    local provider="$1" operation="$2" prefix function_name

    source_registered "$provider" || return 1
    [[ "$operation" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1

    prefix=${PHOENIX_SOURCE_PROVIDERS[$provider]}
    function_name="${prefix}_${operation}"

    declare -F "$function_name" >/dev/null 2>&1 || return 1
    printf '%s\n' "$function_name"
}

source_call_for() {
    local provider="$1" operation="$2" function_name
    shift 2

    function_name=$(source_operation_function "$provider" "$operation") || return 1
    "$function_name" "$@"
}

source_call() {
    local operation="$1"
    local provider="${SOURCE_TRANSPORT:-local}"
    shift

    source_call_for "$provider" "$operation" "$@"
}
