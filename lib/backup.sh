#!/bin/bash

create_backup_context() {
    TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

    LOG_DIR="$PROJECT_ROOT/logs"
    STATUS_DIR="$DESTINATION_STATUS_DIR"
    INVENTORY_DIR="$DESTINATION_MANIFEST_DIR/inventory/$TIMESTAMP"

    LOGFILE="$LOG_DIR/$TIMESTAMP.log"
    MANIFEST="$DESTINATION_MANIFEST_DIR/$TIMESTAMP.txt"
    # shellcheck disable=SC2034 # Consumed by the backup-lock module.
    LOCKFILE="/tmp/project_phoenix_backup.lock"

    destination_prepare_directory "$STATUS_DIR" || return 1
    destination_prepare_directory "$INVENTORY_DIR" || return 1
    mkdir -p "$LOG_DIR"
}


write_backup_header() {
    section "PROJECT PHOENIX BACKUP"

    {
        echo "Project Phoenix v$VERSION"
        echo "Backup ID : $TIMESTAMP"
        echo "Started   : $(date)"
        echo "Host      : $(hostname)"
        echo "Source    : $SOURCE"
        echo "Target    : ${BACKUP_HOST}:${DESTINATION}"
        echo
        echo "-------------------------------------------------------------"
    } | tee "$LOGFILE"
}

verify_backup_ssh() {
    log_info "Testing SSH connection..."

    if ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=10 "${BACKUP_USER}@${BACKUP_HOST}" "echo OK" >>"$LOGFILE" 2>&1; then
        log_success "SSH Connection PASS"
        return 0
    fi

    log_error "SSH Connection FAIL"
    date > "$STATUS_DIR/last_failure"
    return 1
}

verify_backup_destination() {
    log_info "Checking destination..."

    if ssh -i "$SSH_KEY" "${BACKUP_USER}@${BACKUP_HOST}" "test -d '$DESTINATION'" >>"$LOGFILE" 2>&1; then
        log_success "Destination PASS"
        return 0
    fi

    log_error "Destination FAIL"
    date > "$STATUS_DIR/last_failure"
    return 1
}


run_rsync_backup() {
    log_info "Starting rsync..."

    START=$(date +%s)

    rsync -avh \
        --stats \
        --human-readable \
        --exclude-from="$EXCLUDE_FILE" \
        -e "ssh -i $SSH_KEY" \
        "$SOURCE" \
        "${BACKUP_USER}@${BACKUP_HOST}:$DESTINATION" \
        >>"$LOGFILE" 2>&1

    RSYNC_EXIT=$?

    END=$(date +%s)
    DURATION=$((END - START))
}

backup_rsync_copy_status() {
    case "$1" in
        0) printf "%s\n" "clean" ;;
        23) printf "%s\n" "warning" ;;
        *) printf "%s\n" "failure" ;;
    esac
}

backup_rsync_copy_usable() {
    [ "$(backup_rsync_copy_status "$1")" != "failure" ]
}

run_backup_integrity_hook() {
    local rsync_exit_code="$1"
    local generator="${2:-integrity_generate_remote_reference}"

    if ! backup_rsync_copy_usable "$rsync_exit_code"; then
        BACKUP_INTEGRITY_STATUS="skipped"
        return 0
    fi

    if "$generator"; then
        BACKUP_INTEGRITY_STATUS="success"
        return 0
    fi

    BACKUP_INTEGRITY_STATUS="failed"
    return 1
}

backup_set_outcome_status() {
    local copy_status
    local metadata_status="${3:-success}"

    copy_status=$(backup_rsync_copy_status "$1")
    if [ "$copy_status" = "failure" ]; then
        BACKUP_HISTORY_STATUS="failed"
        BACKUP_HISTORY_DETAILS="Backup copy failed; integrity generation skipped"
    elif [ "$metadata_status" != "success" ]; then
        BACKUP_HISTORY_STATUS="partial"
        BACKUP_HISTORY_DETAILS="Backup payload copied; metadata publication $metadata_status at ${BACKUP_METADATA_STAGE:-unknown stage}; integrity=$2"
    elif [ "$2" = "success" ]; then
        if [ "$copy_status" = "warning" ]; then
            BACKUP_HISTORY_STATUS="completed-with-warnings"
            BACKUP_HISTORY_DETAILS="Backup copied with rsync warnings; remote integrity manifest completed"
        else
            BACKUP_HISTORY_STATUS="completed"
            BACKUP_HISTORY_DETAILS="Backup copied cleanly; remote integrity manifest completed"
        fi
    elif [ "$copy_status" = "warning" ]; then
        BACKUP_HISTORY_STATUS="partial"
        BACKUP_HISTORY_DETAILS="Backup copied with rsync warnings; integrity generation failed"
    else
        # shellcheck disable=SC2034 # Consumed by launcher history and tests.
        BACKUP_HISTORY_STATUS="partial"
        # shellcheck disable=SC2034 # Consumed by launcher history and tests.
        BACKUP_HISTORY_DETAILS="Backup copied cleanly; integrity generation failed"
    fi
}

calculate_backup_stats() {
    BACKUP_SIZE=$(ssh -i "$SSH_KEY" "${BACKUP_USER}@${BACKUP_HOST}" "du -sh '$DESTINATION' | awk '{print \$1}'" 2>/dev/null || echo "unknown")
    SOURCE_SIZE=$(du -sh "$SOURCE" | awk '{print $1}')
}

write_backup_manifest() {
    {
        echo "Project Phoenix Backup Manifest"
        echo
        echo "Version: $VERSION"
        echo "Date: $(date)"
        echo "Duration: ${DURATION} seconds"
        echo "Exit Code: $RSYNC_EXIT"
        echo "Source: $SOURCE"
        echo "Source Size: $SOURCE_SIZE"
        echo "Destination: ${BACKUP_HOST}:${DESTINATION}"
        echo "Backup Size: $BACKUP_SIZE"
        echo "Inventory: $INVENTORY_DIR"
        echo "Filesystem Inventory Status: ${BACKUP_FILESYSTEM_INVENTORY_STATUS:-unknown}"
        echo "Docker Runtime Inventory Status: ${BACKUP_DOCKER_INVENTORY_STATUS:-unknown}"
        echo "Inventory Status: ${BACKUP_INVENTORY_STATUS:-unknown}"
        echo "Integrity Status: ${BACKUP_INTEGRITY_STATUS:-skipped}"
        echo "Metadata Status: ${BACKUP_METADATA_STATUS:-skipped}"
        if [ -n "${INTEGRITY_REMOTE_REFERENCE_NAME:-}" ]; then
            echo "Integrity Reference: $INTEGRITY_REMOTE_REFERENCE_NAME"
        fi
    } > "$MANIFEST"
}

write_backup_health_report() {
    local copy_status

    copy_status=$(backup_rsync_copy_status "$RSYNC_EXIT")
    echo | tee -a "$LOGFILE"
    echo "=============================================================" | tee -a "$LOGFILE"
    echo "              PROJECT PHOENIX HEALTH REPORT" | tee -a "$LOGFILE"
    echo "=============================================================" | tee -a "$LOGFILE"
    echo | tee -a "$LOGFILE"

    backup_report_inventory_status | tee -a "$LOGFILE"

    if [ "$copy_status" != "failure" ]; then
        if [ "$copy_status" = "warning" ]; then
            log_warning "Backup completed with rsync warnings" | tee -a "$LOGFILE"
        else
            log_success "Backup Payload PASS" | tee -a "$LOGFILE"
        fi
        if [ "${BACKUP_INTEGRITY_STATUS:-failed}" = "success" ]; then
            log_success "Integrity Manifest PASS" | tee -a "$LOGFILE"
            if [ "$copy_status" = "warning" ]; then
                OVERALL="PROJECT PHOENIX READY WITH RSYNC WARNINGS"
            else
                OVERALL="PROJECT PHOENIX READY"
            fi
        else
            log_warning "Integrity Manifest FAIL - backup data was copied" | tee -a "$LOGFILE"
            OVERALL="PROJECT PHOENIX READY WITH INTEGRITY WARNING"
        fi
        if [ "${BACKUP_METADATA_STATUS:-failed}" != "success" ]; then
            log_warning "Metadata publication ${BACKUP_METADATA_STATUS:-failed} - backup payload remains usable" | tee -a "$LOGFILE"
            OVERALL="PROJECT PHOENIX READY WITH METADATA WARNING"
        fi
        date > "$STATUS_DIR/last_success"
    else
        log_error "Backup FAIL" | tee -a "$LOGFILE"
        OVERALL="PROJECT PHOENIX NEEDS ATTENTION"
        date > "$STATUS_DIR/last_failure"
    fi

    echo | tee -a "$LOGFILE"
    echo "Backup ID   : $TIMESTAMP" | tee -a "$LOGFILE"
    echo "Source Size : $SOURCE_SIZE" | tee -a "$LOGFILE"
    echo "Backup Size : $BACKUP_SIZE" | tee -a "$LOGFILE"
    echo "Duration    : ${DURATION} seconds" | tee -a "$LOGFILE"
    echo "Exit Code   : $RSYNC_EXIT" | tee -a "$LOGFILE"
    echo "Integrity   : ${BACKUP_INTEGRITY_STATUS:-skipped}" | tee -a "$LOGFILE"
    echo "Metadata    : ${BACKUP_METADATA_STATUS:-skipped}" | tee -a "$LOGFILE"
    echo | tee -a "$LOGFILE"

    echo "=============================================================" | tee -a "$LOGFILE"
    echo "                $OVERALL" | tee -a "$LOGFILE"
    echo "=============================================================" | tee -a "$LOGFILE"
}

run_backup() {
    local backup_exit_code

    load_config
    get_version

    if ! create_backup_context; then
        BACKUP_HISTORY_STATUS="failed"
        BACKUP_HISTORY_DETAILS="Destination-local backup state could not be prepared safely"
        return 1
    fi
    if ! acquire_backup_lock; then
        BACKUP_HISTORY_STATUS="failed"
        BACKUP_HISTORY_DETAILS="Backup lock acquisition failed"
        return 1
    fi
    write_backup_header

    if ! verify_backup_ssh; then
        BACKUP_HISTORY_STATUS="failed"
        BACKUP_HISTORY_DETAILS="SSH validation failed before backup"
        backup_lock_finalize_status 1 "SSH validation failure"
        return $?
    fi
    if ! verify_backup_destination; then
        # shellcheck disable=SC2034 # Consumed by launcher history reporting.
        BACKUP_HISTORY_STATUS="failed"
        # shellcheck disable=SC2034 # Consumed by launcher history reporting.
        BACKUP_HISTORY_DETAILS="Destination validation failed before backup"
        backup_lock_finalize_status 1 "destination validation failure"
        return $?
    fi

    if generate_backup_inventory; then :; fi
    run_rsync_backup
    if [ "$BACKUP_FILESYSTEM_INVENTORY_STATUS" = "success" ]; then
        if run_backup_metadata_hook "$RSYNC_EXIT"; then :; fi
    else
        BACKUP_METADATA_STATUS="skipped"
        BACKUP_METADATA_STAGE="filesystem inventory: ${BACKUP_FILESYSTEM_INVENTORY_FAILURE:-unknown failure}"
    fi
    if run_backup_integrity_hook "$RSYNC_EXIT"; then
        :
    fi
    backup_set_outcome_status "$RSYNC_EXIT" "$BACKUP_INTEGRITY_STATUS" "$BACKUP_METADATA_STATUS"
    calculate_backup_stats
    write_backup_manifest
    write_backup_health_report

    backup_exit_code="$RSYNC_EXIT"
    if [ "${BACKUP_METADATA_STATUS:-failed}" != "success" ] && [ "$RSYNC_EXIT" -eq 0 ]; then
        backup_exit_code=23
    fi
    backup_lock_finalize_status "$backup_exit_code" "backup completion"
}
