#!/bin/bash

create_backup_context() {
    TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

    LOG_DIR="$PROJECT_ROOT/logs"
    STATUS_DIR="$PROJECT_ROOT/status"
    MANIFEST_DIR="$PROJECT_ROOT/manifests"
    INVENTORY_DIR="$MANIFEST_DIR/inventory/$TIMESTAMP"

    LOGFILE="$LOG_DIR/$TIMESTAMP.log"
    MANIFEST="$MANIFEST_DIR/$TIMESTAMP.txt"
    LOCKFILE="/tmp/project_phoenix_backup.lock"

    mkdir -p "$LOG_DIR" "$STATUS_DIR" "$MANIFEST_DIR" "$INVENTORY_DIR"
}

acquire_backup_lock() {
    if [ -f "$LOCKFILE" ]; then
        echo "Another Project Phoenix backup appears to be running."
        exit 1
    fi

    touch "$LOCKFILE"

    trap 'rm -f "$LOCKFILE"' EXIT
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

generate_backup_inventory() {
    log_info "Generating inventory..."

    {
        echo "Project Phoenix Inventory"
        echo
        echo "Date: $(date)"
        echo "Host: $(hostname)"
        echo "Version: $VERSION"
        echo "Source: $SOURCE"
        echo "Destination: ${BACKUP_HOST}:${DESTINATION}"
    } > "$INVENTORY_DIR/summary.txt"

    docker ps -a > "$INVENTORY_DIR/containers.txt" 2>&1
    docker images > "$INVENTORY_DIR/images.txt" 2>&1
    docker volume ls > "$INVENTORY_DIR/volumes.txt" 2>&1
    docker network ls > "$INVENTORY_DIR/networks.txt" 2>&1
    docker version > "$INVENTORY_DIR/docker-version.txt" 2>&1
    docker info > "$INVENTORY_DIR/docker-info.txt" 2>&1

    find "$SOURCE" \
        \( -name "docker-compose.yml" -o \
           -name "docker-compose.yaml" -o \
           -name "compose.yml" -o \
           -name "compose.yaml" \) \
        > "$INVENTORY_DIR/compose-files.txt" 2>&1

    du -sh "$SOURCE"/* > "$INVENTORY_DIR/source-folder-sizes.txt" 2>&1

    log_success "Inventory PASS"
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
    } > "$MANIFEST"
}

write_backup_health_report() {
    echo | tee -a "$LOGFILE"
    echo "=============================================================" | tee -a "$LOGFILE"
    echo "              PROJECT PHOENIX HEALTH REPORT" | tee -a "$LOGFILE"
    echo "=============================================================" | tee -a "$LOGFILE"
    echo | tee -a "$LOGFILE"

    if [ -d "$INVENTORY_DIR" ]; then
        log_success "Inventory PASS" | tee -a "$LOGFILE"
    else
        log_error "Inventory FAIL" | tee -a "$LOGFILE"
    fi

    if [ "$RSYNC_EXIT" -eq 0 ]; then
        log_success "Backup PASS" | tee -a "$LOGFILE"
        OVERALL="PROJECT PHOENIX READY"
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
    echo | tee -a "$LOGFILE"

    echo "=============================================================" | tee -a "$LOGFILE"
    echo "                $OVERALL" | tee -a "$LOGFILE"
    echo "=============================================================" | tee -a "$LOGFILE"
}

run_backup() {
    load_config
    get_version

    create_backup_context
    acquire_backup_lock
    write_backup_header

    verify_backup_ssh || exit 1
    verify_backup_destination || exit 1

    generate_backup_inventory
    run_rsync_backup
    calculate_backup_stats
    write_backup_manifest
    write_backup_health_report

    return "$RSYNC_EXIT"
}