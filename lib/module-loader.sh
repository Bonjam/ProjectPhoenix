#!/bin/bash

load_phoenix_modules() {
    local module_file
    local module_name

    for module_file in "$PROJECT_ROOT"/lib/*.sh; do
        [ -f "$module_file" ] || continue

        module_name="$(basename "$module_file")"

        case "$module_name" in
            core.sh|module-loader.sh)
                continue
                ;;
        esac

        # shellcheck source=/dev/null
        source "$module_file"
    done
}