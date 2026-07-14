#!/bin/bash

run_restore() {
    load_config
    get_version

    section "PROJECT PHOENIX RESTORE"

    log_warning "Restore assistant is running in safe preview mode."
    echo

    echo "Version      : $VERSION"
    echo "Project      : $PROJECT_NAME"
    echo "Restore From : $(transport_call restore_source_summary)"
    echo "Restore To   : $SOURCE"
    echo

    section "RESTORE COMMAND"

    transport_call restore_preview_command
    echo

    section "AFTER RESTORE"

    echo "Find Compose files:"
    echo
    echo "find \"$SOURCE\" -name \"docker-compose.yml\" -o -name \"compose.yml\""
    echo

    echo "Start stacks from each Compose folder:"
    echo
    echo "docker compose up -d"
    echo

    log_success "Restore preview complete"
}

restore_normalize_directory() {
    case "$1" in
        */) printf "%s\n" "$1" ;;
        *) printf "%s/\n" "$1" ;;
    esac
}

restore_local_target_accessible() {
    [ -d "$1" ] && [ -r "$1" ] && [ -x "$1" ]
}

restore_local_target_writable() {
    restore_local_target_accessible "$1" && [ -w "$1" ]
}

restore_resolve_target() {
    readlink -f -- "$1" 2>/dev/null
}

restore_target_is_safe() {
    local target="$1"
    local repository_root="$2"
    local normalized_target
    local protected_target
    local resolved_protected_target
    local resolved_target

    [ -n "$target" ] || return 1
    normalized_target="$target"
    while [ "$normalized_target" != "/" ] && [ "${normalized_target%/}" != "$normalized_target" ]; do
        normalized_target="${normalized_target%/}"
    done
    resolved_target=$(restore_resolve_target "$target") || return 1

    for protected_target in / /bin /boot /dev /etc /home /lib /lib64 \
        /proc /root /run /sbin /sys /tmp /usr /var "$repository_root"
    do
        while [ "$protected_target" != "/" ] && [ "${protected_target%/}" != "$protected_target" ]; do
            protected_target="${protected_target%/}"
        done
        [ "$normalized_target" != "$protected_target" ] || return 1

        resolved_protected_target=$(restore_resolve_target "$protected_target") || continue
        [ "$resolved_target" != "$resolved_protected_target" ] || return 1
    done
}

restore_confirmation_matches() {
    [ "$1" = "RESTORE PROJECT PHOENIX" ]
}

restore_execute_dry_run() {
    local rsync_command="$1"
    local key_file="$2"
    local user="$3"
    local host="$4"
    local remote_directory="$5"
    local local_directory="$6"
    local quoted_key
    local ssh_command

    printf -v quoted_key "%q" "$key_file"
    ssh_command="ssh -i $quoted_key -o BatchMode=yes -o StrictHostKeyChecking=accept-new"

    "$rsync_command" -avhn --stats \
        -e "$ssh_command" \
        "${user}@${host}:$(restore_normalize_directory "$remote_directory")" \
        "$(restore_normalize_directory "$local_directory")"
}

restore_execute_confirmed() {
    local rsync_command="$1"
    local key_file="$2"
    local user="$3"
    local host="$4"
    local remote_directory="$5"
    local local_directory="$6"
    local quoted_key
    local ssh_command

    printf -v quoted_key "%q" "$key_file"
    ssh_command="ssh -i $quoted_key -o BatchMode=yes -o StrictHostKeyChecking=accept-new"

    "$rsync_command" -avh --stats \
        -e "$ssh_command" \
        "${user}@${host}:$(restore_normalize_directory "$remote_directory")" \
        "$(restore_normalize_directory "$local_directory")"
}

restore_execute_confirmed_if_ready() {
    local dry_run_exit_code="$1"
    local confirmation="$2"

    shift 2
    [ "$dry_run_exit_code" -eq 0 ] || return 1
    restore_confirmation_matches "$confirmation" || return 2
    restore_execute_confirmed "$@"
}

restore_create_log_file() {
    mkdir -p "$LOG_DIR"
    printf "%s/restore-%s-%s.log\n" \
        "$LOG_DIR" "$(date +%Y%m%d-%H%M%S)" "$$"
}

restore_log() {
    local log_file="$1"
    shift
    printf "%s | %s\n" "$(date "+%Y-%m-%d %H:%M:%S")" "$*" >> "$log_file"
}

restore_parse_rsync_stats() {
    local output="$1"

    RESTORE_DRY_RUN_FILE_COUNT=$(
        printf "%s\n" "$output" |
            sed -n "s/^Number of files: \([^ ]*\).*/\1/p" |
            head -n 1
    )
    RESTORE_DRY_RUN_TRANSFER_SIZE=$(
        printf "%s\n" "$output" |
            sed -n "s/^Total transferred file size: //p" |
            head -n 1
    )
}

run_restore_dry_run() {
    local dry_run_output
    local rsync_exit_code

    if ! validate_config; then
        log_error "Restore dry run stopped because configuration is invalid"
        return 1
    fi

    section "PROJECT PHOENIX RESTORE DRY RUN"

    if ! discovery_has_command rsync; then
        log_error "rsync is not installed"
        return 1
    fi

    if ! transport_call restore_preflight; then
        log_error "Configured backup destination is unavailable"
        return 1
    fi
    log_success "Backup destination is available"

    if [ ! -d "$SOURCE" ]; then
        log_warning "Local restore target does not exist; it will not be created"
        return 1
    fi

    if ! restore_local_target_accessible "$SOURCE"; then
        log_error "Local restore target is not accessible"
        return 1
    fi
    log_success "Local restore target is accessible"

    echo
    printf "%-15s: %s\n" "Backup Source" "$(transport_call restore_source_summary)"
    printf "%-15s: %s\n" "Restore Target" "$(restore_normalize_directory "$SOURCE")"
    echo
    echo "Files that would be restored:"
    echo "--------------------------------"

    if dry_run_output=$(LC_ALL=C transport_call restore_dry_run 2>&1); then
        rsync_exit_code=0
    else
        rsync_exit_code=$?
    fi

    printf "%s\n" "$dry_run_output"
    restore_parse_rsync_stats "$dry_run_output"

    echo
    if [ -n "$RESTORE_DRY_RUN_FILE_COUNT" ]; then
        printf "%-24s: %s\n" "Total File Count" "$RESTORE_DRY_RUN_FILE_COUNT"
    else
        printf "%-24s: %s\n" "Total File Count" "unavailable"
    fi
    if [ -n "$RESTORE_DRY_RUN_TRANSFER_SIZE" ]; then
        printf "%-24s: %s\n" "Estimated Transfer Size" "$RESTORE_DRY_RUN_TRANSFER_SIZE"
    else
        printf "%-24s: %s\n" "Estimated Transfer Size" "unavailable"
    fi
    printf "%-24s: %s\n" "rsync Exit Code" "$rsync_exit_code"
    echo

    if [ "$rsync_exit_code" -eq 0 ]; then
        echo "DRY RUN STATUS: READY"
        echo
        echo "No files were changed."
        return 0
    fi

    echo "DRY RUN STATUS: FAILED"
    echo
    echo "No files were changed."
    return "$rsync_exit_code"
}

run_restore_confirm() {
    local confirmation
    local dry_run_output
    local dry_run_exit_code
    local log_file
    local restore_output
    local rsync_exit_code

    if ! validate_config; then
        log_error "Confirmed restore stopped because configuration is invalid"
        return 1
    fi

    section "PROJECT PHOENIX CONFIRMED RESTORE"

    if ! discovery_has_command rsync; then
        log_error "rsync is not installed"
        return 1
    fi
    if ! transport_call restore_preflight; then
        log_error "Configured backup destination is unavailable"
        return 1
    fi
    log_success "Backup destination is available"

    if [ ! -d "$SOURCE" ]; then
        log_warning "Local restore target does not exist; it will not be created"
        return 1
    fi
    if ! restore_target_is_safe "$SOURCE" "$PROJECT_ROOT"; then
        log_error "Local restore target is protected or unsafe"
        return 1
    fi
    if ! restore_local_target_writable "$SOURCE"; then
        log_error "Local restore target must be readable, searchable, and writable"
        return 1
    fi
    log_success "Local restore target passed safety checks"

    log_file=$(restore_create_log_file)
    : > "$log_file"
    restore_log "$log_file" "Restore started"
    restore_log "$log_file" "Source: $(transport_call restore_source_summary)"
    restore_log "$log_file" "Local target: $(restore_normalize_directory "$SOURCE")"

    echo
    printf "%-15s: %s\n" "Backup Source" "$(transport_call restore_source_summary)"
    printf "%-15s: %s\n" "Restore Target" "$(restore_normalize_directory "$SOURCE")"
    echo
    echo "Running required dry run..."

    if dry_run_output=$(LC_ALL=C transport_call restore_dry_run 2>&1); then
        dry_run_exit_code=0
    else
        dry_run_exit_code=$?
    fi
    restore_parse_rsync_stats "$dry_run_output"
    printf "%s\n" "$dry_run_output"
    restore_log "$log_file" "Dry-run exit code: $dry_run_exit_code"
    restore_log "$log_file" "Dry-run file count: ${RESTORE_DRY_RUN_FILE_COUNT:-unavailable}"
    restore_log "$log_file" "Dry-run transfer size: ${RESTORE_DRY_RUN_TRANSFER_SIZE:-unavailable}"

    echo
    printf "%-24s: %s\n" "Dry-run File Count" "${RESTORE_DRY_RUN_FILE_COUNT:-unavailable}"
    printf "%-24s: %s\n" "Estimated Transfer Size" "${RESTORE_DRY_RUN_TRANSFER_SIZE:-unavailable}"
    printf "%-24s: %s\n" "Dry-run Exit Code" "$dry_run_exit_code"

    if [ "$dry_run_exit_code" -ne 0 ]; then
        restore_log "$log_file" "Final status: failed before confirmation"
        write_history_entry "restore-confirm" "failed" "Restore dry run failed"
        echo
        echo "RESTORE STATUS: FAILED"
        echo
        echo "Review the restore log: $log_file"
        return "$dry_run_exit_code"
    fi

    echo
    echo "============================================================="
    echo "WARNING: THIS WILL COPY FILES INTO THE LOCAL RESTORE TARGET"
    echo "============================================================="
    echo "Type exactly: RESTORE PROJECT PHOENIX"
    read -r confirmation

    if ! restore_confirmation_matches "$confirmation"; then
        restore_log "$log_file" "Confirmation cancelled"
        restore_log "$log_file" "Final status: cancelled"
        write_history_entry "restore-confirm" "cancelled" "Restore cancelled before file transfer"
        echo
        echo "RESTORE STATUS: CANCELLED"
        echo
        echo "No files were changed."
        return 2
    fi

    restore_log "$log_file" "Confirmation accepted"
    echo
    echo "Starting confirmed restore..."

    if restore_output=$(transport_call restore_confirmed 2>&1); then
        rsync_exit_code=0
    else
        rsync_exit_code=$?
    fi

    printf "%s\n" "$restore_output"
    printf "%s\n" "$restore_output" >> "$log_file"
    restore_log "$log_file" "rsync exit code: $rsync_exit_code"

    if [ "$rsync_exit_code" -eq 0 ]; then
        restore_log "$log_file" "Final status: complete"
        write_history_entry "restore-confirm" "success" "Confirmed restore completed"
        echo
        echo "RESTORE STATUS: COMPLETE"
        echo
        echo "Files have been copied to:"
        restore_normalize_directory "$SOURCE"
        echo
        echo "Docker containers were not started."
        echo "Review the restored files before starting services."
        return 0
    fi

    restore_log "$log_file" "Final status: failed"
    write_history_entry "restore-confirm" "failed" "Confirmed restore failed"
    echo
    echo "RESTORE STATUS: FAILED"
    echo
    echo "Review the restore log: $log_file"
    return "$rsync_exit_code"
}
