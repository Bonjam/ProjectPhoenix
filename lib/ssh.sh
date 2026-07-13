#!/bin/bash

ssh_key_exists() {
    local key_file="$1"

    [ -f "$key_file" ]
}

ssh_generate_key() {
    local key_file="$1"

    if ! command -v ssh-keygen >/dev/null 2>&1; then
        log_error "ssh-keygen is not installed"
        return 1
    fi

    mkdir -p "$(dirname "$key_file")"

    ssh-keygen \
        -t ed25519 \
        -f "$key_file" \
        -N "" \
        -C "project-phoenix" \
        >/dev/null 2>&1
}

ssh_test_connection() {
    local key_file="$1"
    local user="$2"
    local host="$3"
    local strict_host_key_checking="${4:-accept-new}"

    ssh \
        -i "$key_file" \
        -o BatchMode=yes \
        -o ConnectTimeout=8 \
        -o "StrictHostKeyChecking=$strict_host_key_checking" \
        "${user}@${host}" \
        "printf '%s\n' PROJECT_PHOENIX_SSH_OK" \
        2>/dev/null |
        grep -q "PROJECT_PHOENIX_SSH_OK"
}

ssh_remote_destination_exists() {
    local key_file="$1"
    local user="$2"
    local host="$3"
    local destination="$4"
    local strict_host_key_checking="${5:-ask}"

    printf '%s\n' "$destination" |
        ssh \
            -i "$key_file" \
            -o BatchMode=yes \
            -o ConnectTimeout=8 \
            -o "StrictHostKeyChecking=$strict_host_key_checking" \
            "${user}@${host}" \
            'IFS= read -r destination; test -d "$destination"' \
            >/dev/null 2>&1
}

ssh_run_read_only_destination_script() {
    local key_file="$1"
    local user="$2"
    local host="$3"
    local destination="$4"
    local strict_host_key_checking="${5:-accept-new}"
    local remote_shell="${6:-sh}"

    case "$remote_shell" in
        sh|bash) ;;
        *) return 1 ;;
    esac

    {
        printf "%s\n" "$destination"
        cat
    } | ssh \
        -i "$key_file" \
        -o BatchMode=yes \
        -o ConnectTimeout=8 \
        -o "StrictHostKeyChecking=$strict_host_key_checking" \
        "${user}@${host}" \
        "IFS= read -r destination; export destination; $remote_shell -s"
}

ssh_run_destination_script() {
    local key_file="$1"
    local user="$2"
    local host="$3"
    local destination="$4"
    local strict_host_key_checking="${5:-accept-new}"
    {
        printf "%s\n" "$destination"
        cat
    } | ssh -i "$key_file" -o BatchMode=yes -o ConnectTimeout=8 \
        -o "StrictHostKeyChecking=$strict_host_key_checking" \
        "${user}@${host}" \
        "IFS= read -r destination; export destination; bash -s"
}
