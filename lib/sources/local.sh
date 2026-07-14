#!/bin/bash

source_local_configure() {
    SOURCE_PATH="${SOURCE_PATH:-${SOURCE:-}}"
    SOURCE="$SOURCE_PATH"
}

source_local_validate_config() {
    [ -n "${SOURCE_PATH:-}" ] &&
        [[ "$SOURCE_PATH" = /* ]] &&
        [[ "$SOURCE_PATH" != *$'\n'* ]] &&
        [[ "$SOURCE_PATH" != *$'\r'* ]] &&
        [[ "$SOURCE_PATH" != *$'\t'* ]]
}

source_local_info() {
    printf "%-22s: %s\n" "Path" "${SOURCE_PATH:-not set}"
}

source_local_check() {
    local failures=0

    if ! source_local_validate_config; then
        printf "%-24s: FAIL\n" "Configuration"
        echo
        echo "SOURCE CHECK: FAIL"
        return 1
    fi

    printf "%-24s: %s\n" "Path" "$SOURCE_PATH"

    if [ -d "$SOURCE_PATH" ] && [ ! -L "$SOURCE_PATH" ]; then
        printf "%-24s: yes\n" "Exists"
    else
        printf "%-24s: no\n" "Exists"
        failures=$((failures + 1))
    fi

    if [ -r "$SOURCE_PATH" ] && [ -x "$SOURCE_PATH" ]; then
        printf "%-24s: PASS\n" "Readable"
    else
        printf "%-24s: FAIL\n" "Readable"
        failures=$((failures + 1))
    fi

    if discovery_has_command find; then
        printf "%-24s: PASS\n" "find"
    else
        printf "%-24s: FAIL\n" "find"
        failures=$((failures + 1))
    fi

    if discovery_has_command du; then
        printf "%-24s: PASS\n" "du"
    else
        printf "%-24s: FAIL\n" "du"
        failures=$((failures + 1))
    fi

    echo
    if [ "$failures" -eq 0 ]; then
        echo "SOURCE CHECK: PASS"
        return 0
    fi

    echo "SOURCE CHECK: FAIL"
    return 1
}

source_local_summary() {
    printf '%s\n' "${SOURCE_PATH:-not-set}"
}

source_local_backup_prepare() {
    source_local_validate_config &&
        [ -d "$SOURCE_PATH" ] &&
        [ ! -L "$SOURCE_PATH" ] &&
        [ -r "$SOURCE_PATH" ] &&
        [ -x "$SOURCE_PATH" ]
}

source_local_transfer_to_local() {
    local destination_path="$1"
    local exclude_file="$2"
    local source_path="${SOURCE_PATH:-${SOURCE:-}}"

    [ -n "$source_path" ] || return 1

    rsync -avh --stats --human-readable \
        --exclude-from="$exclude_file" \
        "${source_path%/}/" "${destination_path%/}/"
}

source_local_inventory_compose_files() {
    find "$SOURCE_PATH" -type f \
        \( -name docker-compose.yml -o \
           -name docker-compose.yaml -o \
           -name compose.yml -o \
           -name compose.yaml \) \
        -print
}

source_local_inventory_source_sizes() {
    local entry

    while IFS= read -r -d "" entry; do
        du -sh -- "$entry" || return 1
    done < <(find "$SOURCE_PATH" -mindepth 1 -maxdepth 1 -print0)
}

source_local_size() {
    du -sh -- "$SOURCE_PATH" 2>/dev/null | awk '{print $1}'
}

source_register local source_local
