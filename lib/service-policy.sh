#!/bin/bash

service_policy_normalize_path() {
    [ -n "$1" ] || return 1
    readlink -m -- "$1" 2>/dev/null
}

service_policy_path_is_production_docker() {
    local normalized_path

    normalized_path=$(service_policy_normalize_path "$1") || return 1
    case "$normalized_path" in
        /volume2/docker|/volume2/docker/*) return 0 ;;
        *) return 1 ;;
    esac
}

service_policy_classify_source() {
    if service_policy_path_is_production_docker "$1"; then
        printf "%s\n" "required"
    else
        printf "%s\n" "advisory"
    fi
}

service_policy_resolve_for_source() {
    local configured_mode="${1:-auto}"
    local source_path="$2"

    case "$configured_mode" in
        required|advisory|disabled) printf "%s\n" "$configured_mode" ;;
        *) service_policy_classify_source "$source_path" ;;
    esac
}
