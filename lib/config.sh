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
}