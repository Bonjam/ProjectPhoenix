#!/bin/bash

load_config() {
    local config_file="${PROJECT_ROOT}/config.conf"

    if [ ! -f "$config_file" ]; then
        echo "ERROR: Missing config file:"
        echo "$config_file"
        echo
        echo "Create one from:"
        echo "examples/config.example.conf"
        exit 1
    fi

    # shellcheck source=/dev/null
    source "$config_file"
    destination_resolve_context || exit 1
    source_resolve_context || exit 1
}

load_config_if_exists() {
    local config_file="${PROJECT_ROOT}/config.conf"

    [ -f "$config_file" ] || return 1

    # shellcheck source=/dev/null
    source "$config_file"
    destination_resolve_context || return 1
    source_resolve_context
}
