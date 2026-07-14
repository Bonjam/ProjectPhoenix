#!/bin/bash

load_phoenix_modules() {
    local module_file
    local module_name
    local transport_file

    for module_file in "$PROJECT_ROOT"/lib/*.sh; do
        [ -f "$module_file" ] || continue
        module_name="$(basename "$module_file")"
        case "$module_name" in
            core.sh|module-loader.sh) continue ;;
        esac
        # shellcheck source=/dev/null
        source "$module_file"
    done

    for transport_file in "$PROJECT_ROOT"/lib/transports/*.sh; do
        [ -f "$transport_file" ] || continue
        # shellcheck source=/dev/null
        source "$transport_file"
    done

    for source_file in "$PROJECT_ROOT"/lib/sources/*.sh; do
        [ -f "$source_file" ] || continue
        # shellcheck source=/dev/null
        source "$source_file"
    done
}
