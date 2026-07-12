#!/bin/bash

run_restore() {
    load_config
    get_version

    section "PROJECT PHOENIX RESTORE"

    log_warning "Restore assistant is running in safe preview mode."
    echo

    echo "Version      : $VERSION"
    echo "Project      : $PROJECT_NAME"
    echo "Restore From : ${BACKUP_USER}@${BACKUP_HOST}:${DESTINATION}"
    echo "Restore To   : $SOURCE"
    echo

    section "RESTORE COMMAND"

    echo "rsync -avh -e \"ssh -i $SSH_KEY\" ${BACKUP_USER}@${BACKUP_HOST}:${DESTINATION} $SOURCE"
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

    if ! ssh_key_exists "$SSH_KEY"; then
        log_error "Configured SSH key file does not exist"
        return 1
    fi

    if ! ssh_test_connection "$SSH_KEY" "$BACKUP_USER" "$BACKUP_HOST" accept-new; then
        log_error "SSH connection failed"
        return 1
    fi
    log_success "SSH connection successful"

    if ! ssh_remote_destination_exists \
        "$SSH_KEY" "$BACKUP_USER" "$BACKUP_HOST" "$DESTINATION" \
        accept-new; then
        log_error "Backup destination was not found"
        return 1
    fi
    log_success "Backup destination found"

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
    printf "%-15s: %s\n" "Remote Backup" "${BACKUP_USER}@${BACKUP_HOST}:$(restore_normalize_directory "$DESTINATION")"
    printf "%-15s: %s\n" "Restore Target" "$(restore_normalize_directory "$SOURCE")"
    echo
    echo "Files that would be restored:"
    echo "--------------------------------"

    if dry_run_output=$(LC_ALL=C restore_execute_dry_run \
        rsync "$SSH_KEY" "$BACKUP_USER" "$BACKUP_HOST" \
        "$DESTINATION" "$SOURCE" 2>&1); then
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
