#!/bin/bash

source_ssh_configure() {
    SOURCE_PATH="${SOURCE_PATH:-${SOURCE:-}}"
    SOURCE="${SOURCE_PATH:-}"
}

source_ssh_value_safe() {
    [ -n "$1" ] &&
        [[ "$1" != *$'\n'* ]] &&
        [[ "$1" != *$'\r'* ]] &&
        [[ "$1" != *$'\t'* ]]
}

source_ssh_path_safe() {
    local path="$1"

    source_ssh_value_safe "$path" || return 1
    [[ "$path" = /* ]] || return 1

    case "/$path/" in
        */../*|*/./*) return 1 ;;
    esac

    [ "$path" != "/" ]
}

source_ssh_validate_config() {
    source_ssh_value_safe "${SOURCE_HOST:-}" &&
        source_ssh_value_safe "${SOURCE_USER:-}" &&
        source_ssh_value_safe "${SOURCE_SSH_KEY:-}" &&
        source_ssh_path_safe "${SOURCE_PATH:-}"
}

source_ssh_info() {
    printf "%-22s: %s\n" "Host" "${SOURCE_HOST:-not set}"
    printf "%-22s: %s\n" "User" "${SOURCE_USER:-not set}"
    printf "%-22s: %s\n" "Path" "${SOURCE_PATH:-not set}"
    printf "%-22s: %s\n" "SSH Key" "${SOURCE_SSH_KEY:-not set}"
}

source_ssh_check() {
    local failures=0 endpoint

    if ! source_ssh_validate_config; then
        printf "%-24s: FAIL\n" "Configuration"
        echo
        echo "SOURCE CHECK: FAIL"
        return 1
    fi

    endpoint="${SOURCE_USER}@${SOURCE_HOST}"

    printf "%-24s: %s\n" "Endpoint" "$endpoint"
    printf "%-24s: %s\n" "Path" "$SOURCE_PATH"

    if discovery_has_command ssh; then
        printf "%-24s: PASS\n" "SSH Client"
    else
        printf "%-24s: FAIL\n" "SSH Client"
        failures=$((failures + 1))
    fi

    if discovery_has_command rsync; then
        printf "%-24s: PASS\n" "Local rsync"
    else
        printf "%-24s: FAIL\n" "Local rsync"
        failures=$((failures + 1))
    fi

    if [ -f "$SOURCE_SSH_KEY" ] && [ ! -L "$SOURCE_SSH_KEY" ]; then
        printf "%-24s: PASS\n" "SSH Key"
    else
        printf "%-24s: FAIL\n" "SSH Key"
        failures=$((failures + 1))
    fi

    if [ "$failures" -eq 0 ] &&
        ssh \
            -i "$SOURCE_SSH_KEY" \
            -o BatchMode=yes \
            -o ConnectTimeout=10 \
            "$endpoint" \
            sh -s -- "$SOURCE_PATH" <<'REMOTE_CHECK'
path=$1
test -d "$path" && test -r "$path"
REMOTE_CHECK
    then
        printf "%-24s: PASS\n" "Connection"
        printf "%-24s: PASS\n" "Source Readable"
    else
        printf "%-24s: FAIL\n" "Connection"
        printf "%-24s: FAIL\n" "Source Readable"
        failures=$((failures + 1))
    fi

    if [ "$failures" -eq 0 ] &&
        ssh \
            -i "$SOURCE_SSH_KEY" \
            -o BatchMode=yes \
            -o ConnectTimeout=10 \
            "$endpoint" \
            'command -v rsync >/dev/null 2>&1'; then
        printf "%-24s: PASS\n" "Remote rsync"
    else
        printf "%-24s: FAIL\n" "Remote rsync"
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

source_ssh_summary() {
    printf '%s@%s:%s\n' \
        "${SOURCE_USER:-not-set}" \
        "${SOURCE_HOST:-not-set}" \
        "${SOURCE_PATH:-not-set}"
}

source_register ssh source_ssh
