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

source_register local source_local
