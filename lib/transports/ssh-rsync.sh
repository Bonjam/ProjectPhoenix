#!/bin/bash

transport_ssh_rsync_configure() {
    DESTINATION_PATH="${DESTINATION_PATH:-${DESTINATION:-}}"
    DESTINATION="${DESTINATION:-$DESTINATION_PATH}"
}

transport_ssh_rsync_validate_config() {
    transport_config_value_present "${DESTINATION:-}" &&
        transport_config_value_present "${BACKUP_HOST:-}" &&
        transport_config_value_present "${BACKUP_USER:-}" &&
        transport_config_value_present "${SSH_KEY:-}"
}

transport_ssh_rsync_inspect_config() {
    # destination-info inspects the resolved profile only. Missing SSH endpoint
    # settings are reported as "not set" and are enforced by operational
    # requirements, health, backup, restore, and integrity commands instead.
    if [ -n "${DESTINATION:-}" ]; then
        transport_config_value_present "$DESTINATION" || return 1
    fi
    if [ -n "${BACKUP_HOST:-}" ]; then
        transport_config_value_present "$BACKUP_HOST" || return 1
    fi
    if [ -n "${BACKUP_USER:-}" ]; then
        transport_config_value_present "$BACKUP_USER" || return 1
    fi
    return 0
}

transport_ssh_rsync_endpoint_summary() {
    printf "%s@%s:%s\n" "${BACKUP_USER:-not-set}" "${BACKUP_HOST:-not-set}" "${DESTINATION:-not-set}"
}

transport_ssh_rsync_filesystem_summary() {
    printf "%s\n" "Remote filesystem over SSH"
}

transport_ssh_rsync_info() {
    printf "%-22s: %s\n" "Host" "${BACKUP_HOST:-not set}"
    printf "%-22s: %s\n" "User" "${BACKUP_USER:-not set}"
    printf "%-22s: %s\n" "Path" "${DESTINATION:-not set}"
}

transport_ssh_rsync_requirements() {
    discovery_has_command ssh && discovery_has_command rsync
}

transport_ssh_rsync_backup_prepare() {
    verify_backup_ssh && verify_backup_destination
}

transport_ssh_rsync_backup_transfer() {
    rsync -avh --stats --human-readable --exclude-from="$EXCLUDE_FILE" \
        -e "ssh -i $SSH_KEY" "$SOURCE" \
        "${BACKUP_USER}@${BACKUP_HOST}:$DESTINATION"
}

transport_ssh_rsync_publish_metadata() {
    backup_publish_metadata_ssh
}

transport_ssh_rsync_destination_size() {
    ssh -i "$SSH_KEY" "${BACKUP_USER}@${BACKUP_HOST}" \
        "du -sh '$DESTINATION' | awk '{print \$1}'" 2>/dev/null
}

transport_ssh_rsync_generate_integrity_reference() {
    integrity_generate_remote_reference_ssh
}

transport_ssh_rsync_integrity_fetch_preflight() {
    ssh_key_exists "$SSH_KEY" && ssh_test_connection "$SSH_KEY" "$BACKUP_USER" "$BACKUP_HOST" accept-new
}

transport_ssh_rsync_download_integrity_reference() {
    integrity_download_remote_reference "$1"
}

transport_ssh_rsync_integrity_directory() {
    printf "%s\n" "${DESTINATION%/}/backup/manifests/integrity"
}

transport_ssh_rsync_retention_preflight() {
    ssh_key_exists "$SSH_KEY" && ssh_test_connection "$SSH_KEY" "$BACKUP_USER" "$BACKUP_HOST" accept-new
}

transport_ssh_rsync_retention_analysis() {
    retention_remote_analysis_ssh
}

transport_ssh_rsync_retention_delete() {
    retention_delete_remote_eligible_ssh "$1"
}

transport_ssh_rsync_recovery_preflight() {
    discovery_has_command ssh && ssh_key_exists "$SSH_KEY" &&
        ssh_test_connection "$SSH_KEY" "$BACKUP_USER" "$BACKUP_HOST" accept-new &&
        ssh_remote_destination_exists "$SSH_KEY" "$BACKUP_USER" "$BACKUP_HOST" "$DESTINATION" accept-new
}

transport_ssh_rsync_recovery_analysis() {
    recovery_remote_analysis
}

transport_ssh_rsync_restore_preflight() {
    ssh_key_exists "$SSH_KEY" &&
        ssh_test_connection "$SSH_KEY" "$BACKUP_USER" "$BACKUP_HOST" accept-new &&
        ssh_remote_destination_exists "$SSH_KEY" "$BACKUP_USER" "$BACKUP_HOST" \
            "$DESTINATION" accept-new
}

transport_ssh_rsync_restore_source_summary() {
    printf "%s@%s:%s\n" "$BACKUP_USER" "$BACKUP_HOST" \
        "$(restore_normalize_directory "$DESTINATION")"
}

transport_ssh_rsync_restore_preview_command() {
    printf 'rsync -avh -e "ssh -i %s" %s@%s:%s %s\n' \
        "$SSH_KEY" "$BACKUP_USER" "$BACKUP_HOST" "$DESTINATION" "$SOURCE"
}

transport_ssh_rsync_restore_dry_run() {
    restore_execute_dry_run rsync "$SSH_KEY" "$BACKUP_USER" "$BACKUP_HOST" \
        "$DESTINATION" "$SOURCE"
}

transport_ssh_rsync_restore_confirmed() {
    restore_execute_confirmed rsync "$SSH_KEY" "$BACKUP_USER" "$BACKUP_HOST" \
        "$DESTINATION" "$SOURCE"
}

transport_register ssh-rsync transport_ssh_rsync
