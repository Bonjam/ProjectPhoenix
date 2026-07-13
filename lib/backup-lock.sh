#!/bin/bash

backup_lock_process_start() {
    local pid="$1" process_stat remaining process_start
    local -a stat_fields=()

    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
    [ -r "/proc/$pid/stat" ] || return 1
    IFS= read -r process_stat < "/proc/$pid/stat" || return 1
    remaining="${process_stat##*) }"
    [ "$remaining" != "$process_stat" ] || return 1
    read -r -a stat_fields <<< "$remaining"
    [ "${#stat_fields[@]}" -ge 20 ] || return 1
    process_start="${stat_fields[19]}"
    [[ "$process_start" =~ ^[0-9]+$ ]] || return 1
    printf "%s\n" "$process_start"
}
backup_lock_process_matches_backup() {
    local pid="$1" expected_start="$2" current_start command_line

    [[ "$expected_start" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    current_start=$(backup_lock_process_start "$pid") || return 1
    [ "$current_start" = "$expected_start" ] || return 1
    [ -r "/proc/$pid/cmdline" ] || return 1
    command_line=$(tr '\0' ' ' < "/proc/$pid/cmdline") || return 1
    case "$command_line" in
        *phoenix.sh*" backup "*) return 0 ;;
        *) return 1 ;;
    esac
}

backup_lock_read_metadata() {
    local lock_path="$1" key value owner_uid link_count

    BACKUP_LOCK_METADATA_PID=""
    BACKUP_LOCK_METADATA_STARTED=""
    BACKUP_LOCK_METADATA_PROCESS_START=""
    BACKUP_LOCK_METADATA_TOKEN=""
    BACKUP_LOCK_METADATA_FINGERPRINT=""

    [ ! -L "$lock_path" ] || return 2
    [ -f "$lock_path" ] || return 2
    [ -r "$lock_path" ] || return 2
    owner_uid=$(stat -c %u -- "$lock_path" 2>/dev/null) || return 2
    [ "$owner_uid" = "$(id -u)" ] || return 2
    link_count=$(stat -c %h -- "$lock_path" 2>/dev/null) || return 2
    [ "$link_count" = "1" ] || return 2
    BACKUP_LOCK_METADATA_FINGERPRINT=$(stat -c '%d:%i:%s:%Y' -- "$lock_path" 2>/dev/null) || return 2

    while IFS='=' read -r key value; do
        case "$key" in
            pid) BACKUP_LOCK_METADATA_PID="$value" ;;
            started) BACKUP_LOCK_METADATA_STARTED="$value" ;;
            hostname) : ;;
            process_start) BACKUP_LOCK_METADATA_PROCESS_START="$value" ;;
            owner_token) BACKUP_LOCK_METADATA_TOKEN="$value" ;;
        esac
    done < "$lock_path" || return 2
}

backup_lock_classify_existing() {
    local lock_path="$1"
    local process_checker="${2:-backup_lock_process_matches_backup}"

    backup_lock_read_metadata "$lock_path" || return 2
    if [[ "$BACKUP_LOCK_METADATA_PID" =~ ^[1-9][0-9]*$ ]] &&
        "$process_checker" "$BACKUP_LOCK_METADATA_PID" \
            "$BACKUP_LOCK_METADATA_PROCESS_START"; then
        return 0
    fi
    return 1
}

backup_lock_remove_stale() {
    local lock_path="$1" expected_fingerprint="$2" current_fingerprint owner_uid

    [ ! -L "$lock_path" ] && [ -f "$lock_path" ] || return 1
    owner_uid=$(stat -c %u -- "$lock_path" 2>/dev/null) || return 1
    [ "$owner_uid" = "$(id -u)" ] || return 1
    current_fingerprint=$(stat -c '%d:%i:%s:%Y' -- "$lock_path" 2>/dev/null) || return 1
    [ "$current_fingerprint" = "$expected_fingerprint" ] || return 1
    rm -f -- "$lock_path"
}

backup_lock_write_candidate() {
    local candidate="$1" owner_token="$2" process_start started host_name

    process_start=$(backup_lock_process_start "$$") || return 1
    started=$(date -u +%Y-%m-%dT%H:%M:%SZ) || return 1
    host_name=$(hostname 2>/dev/null || printf "%s" "unknown")
    {
        printf "pid=%s\n" "$$"
        printf "started=%s\n" "$started"
        printf "hostname=%s\n" "$host_name"
        printf "process_start=%s\n" "$process_start"
        printf "owner_token=%s\n" "$owner_token"
    } > "$candidate"
}

backup_lock_acquire_path() {
    local lock_path="$1"
    local process_checker="${2:-backup_lock_process_matches_backup}"
    local candidate owner_token stale_pid stale_fingerprint _attempt

    BACKUP_LOCK_RECOVERED_PID=""
    BACKUP_LOCK_ACTIVE_PID=""
    BACKUP_LOCK_ACTIVE_STARTED=""
    BACKUP_LOCK_OWNER_TOKEN=""
    for _attempt in 1 2 3; do
        candidate=$(mktemp "${lock_path}.candidate.XXXXXX") || return 2
        owner_token="$$-$(backup_lock_process_start "$$")-$(date +%s)-${RANDOM}"
        if ! backup_lock_write_candidate "$candidate" "$owner_token"; then
            rm -f -- "$candidate"
            return 2
        fi
        if ln -- "$candidate" "$lock_path" 2>/dev/null; then
            rm -f -- "$candidate"
            BACKUP_LOCK_OWNER_TOKEN="$owner_token"
            return 0
        fi
        rm -f -- "$candidate"

        if backup_lock_classify_existing "$lock_path" "$process_checker"; then
            BACKUP_LOCK_ACTIVE_PID="$BACKUP_LOCK_METADATA_PID"
            BACKUP_LOCK_ACTIVE_STARTED="$BACKUP_LOCK_METADATA_STARTED"
            return 1
        else
            case "$?" in
                1)
                    stale_pid="${BACKUP_LOCK_METADATA_PID:-unknown}"
                    stale_fingerprint="$BACKUP_LOCK_METADATA_FINGERPRINT"
                    backup_lock_remove_stale "$lock_path" "$stale_fingerprint" || return 2
                    BACKUP_LOCK_RECOVERED_PID="$stale_pid"
                    ;;
                *) return 2 ;;
            esac
        fi
    done
    return 2
}

backup_lock_cleanup_path() {
    local lock_path="$1" owner_token="$2"

    BACKUP_LOCK_CLEANUP_REASON=""
    if [ ! -e "$lock_path" ] && [ ! -L "$lock_path" ]; then
        return 0
    fi
    if [ -z "$owner_token" ]; then
        BACKUP_LOCK_CLEANUP_REASON="owner token is unavailable"
        return 1
    fi
    if ! backup_lock_read_metadata "$lock_path"; then
        BACKUP_LOCK_CLEANUP_REASON="lock is unsafe, unreadable, or not owned by this user"
        return 1
    fi
    if [ "$BACKUP_LOCK_METADATA_TOKEN" != "$owner_token" ]; then
        BACKUP_LOCK_CLEANUP_REASON="owner token does not match"
        return 1
    fi
    if [ "$BACKUP_LOCK_METADATA_PID" != "$$" ]; then
        BACKUP_LOCK_CLEANUP_REASON="lock PID is owned by another process"
        return 1
    fi
    if ! rm -f -- "$lock_path"; then
        BACKUP_LOCK_CLEANUP_REASON="lock file could not be removed"
        return 1
    fi
}

backup_lock_cleanup() {
    backup_lock_cleanup_path "$LOCKFILE" "${BACKUP_LOCK_OWNER_TOKEN:-}"
}

backup_lock_log_cleanup_failure() {
    local cleanup_stage="$1"

    log_warning "Backup lock cleanup failed"
    printf "Lock Path : %s\n" "${LOCKFILE:-unknown}"
    printf "Stage     : %s\n" "$cleanup_stage"
    printf "Reason    : %s\n" "${BACKUP_LOCK_CLEANUP_REASON:-unknown}"
}

backup_lock_cleanup_exit() {
    local cleanup_stage="${1:-EXIT safety handler}"

    backup_lock_cleanup || {
        backup_lock_log_cleanup_failure "$cleanup_stage"
        return 1
    }
}

backup_lock_signal_cleanup() {
    case "${1:-}" in
        INT|TERM|HUP) backup_lock_cleanup_exit "$1 signal handler" ;;
        *) return 1 ;;
    esac
}

backup_lock_install_traps() {
    phoenix_trap_register backup-lock 'backup_lock_cleanup_exit' EXIT || return 1
    phoenix_trap_register backup-lock 'backup_lock_signal_cleanup HUP' HUP || return 1
    phoenix_trap_register backup-lock 'backup_lock_signal_cleanup INT' INT || return 1
    phoenix_trap_register backup-lock 'backup_lock_signal_cleanup TERM' TERM || return 1
}

backup_lock_release() {
    local cleanup_stage="$1"

    if ! backup_lock_cleanup; then
        backup_lock_log_cleanup_failure "$cleanup_stage"
        return 1
    fi
    phoenix_trap_unregister backup-lock EXIT HUP INT TERM
    BACKUP_LOCK_OWNER_TOKEN=""
}

backup_lock_finalize_status() {
    local backup_status="$1" cleanup_stage="$2"

    backup_lock_release "$cleanup_stage" || return 1
    return "$backup_status"
}

acquire_backup_lock() {
    local lock_result

    if backup_lock_acquire_path "$LOCKFILE"; then
        [ -z "$BACKUP_LOCK_RECOVERED_PID" ] || \
            log_warning "Recovered stale backup lock from PID $BACKUP_LOCK_RECOVERED_PID"
        if ! backup_lock_install_traps; then
            phoenix_trap_unregister backup-lock EXIT HUP INT TERM
            if backup_lock_cleanup; then
                log_error "Backup lock cleanup traps could not be installed"
            else
                backup_lock_log_cleanup_failure "lock acquisition"
            fi
            return 1
        fi
        log_success "Backup lock acquired"
        return 0
    else
        lock_result=$?
    fi
    if [ "$lock_result" -eq 1 ]; then
        log_error "Another Project Phoenix backup is active"
        printf "Active PID: %s\n" "$BACKUP_LOCK_ACTIVE_PID"
        printf "Started   : %s\n" "${BACKUP_LOCK_ACTIVE_STARTED:-unknown}"
    else
        log_error "Backup lock is unsafe or could not be acquired"
    fi
    return 1
}
