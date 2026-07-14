#!/bin/bash

# Transport providers register a stable name and a focused function prefix.
declare -gA PHOENIX_TRANSPORT_PROVIDERS=()

transport_register() {
    local transport="$1" prefix="$2"
    [[ "$transport" =~ ^[a-z0-9][a-z0-9-]*$ ]] || return 1
    [[ "$prefix" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1
    [ -z "${PHOENIX_TRANSPORT_PROVIDERS[$transport]:-}" ] ||
        [ "${PHOENIX_TRANSPORT_PROVIDERS[$transport]}" = "$prefix" ] || return 1
    PHOENIX_TRANSPORT_PROVIDERS["$transport"]="$prefix"
}

transport_registered() {
    [ -n "${PHOENIX_TRANSPORT_PROVIDERS[$1]:-}" ]
}

transport_operation_function() {
    local transport="$1" operation="$2" prefix function_name
    transport_registered "$transport" || return 1
    [[ "$operation" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1
    prefix=${PHOENIX_TRANSPORT_PROVIDERS[$transport]}
    function_name="${prefix}_${operation}"
    declare -F "$function_name" >/dev/null 2>&1 || return 1
    printf "%s\n" "$function_name"
}

transport_call_for() {
    local transport="$1" operation="$2" function_name
    shift 2
    function_name=$(transport_operation_function "$transport" "$operation") || return 1
    "$function_name" "$@"
}

transport_call() {
    local operation="$1"
    shift
    transport_call_for "$DESTINATION_TRANSPORT" "$operation" "$@"
}

transport_config_value_present() {
    [ -n "$1" ] && [[ "$1" != *$'\n'* && "$1" != *$'\r'* && "$1" != *$'\t'* ]]
}
