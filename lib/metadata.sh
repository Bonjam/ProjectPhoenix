#!/bin/bash

backup_metadata_id_safe() {
    [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

backup_publish_metadata_local() {
    local inventory_source="$1" guide_source="$2" backup_root="$3" backup_id="$4"
    local inventory_parent="$backup_root/manifests/inventory"
    local inventory_target="$inventory_parent/$backup_id"
    local restore_directory="$backup_root/restore"
    local guide_target="$restore_directory/README.md"
    local inventory_staging guide_staging

    backup_metadata_id_safe "$backup_id" || return 1
    [ -d "$inventory_source" ] && [ -f "$guide_source" ] || return 1
    mkdir -p "$inventory_parent" "$restore_directory" || return 1
    inventory_staging=$(mktemp -d "$inventory_parent/.inventory-stage.XXXXXX") || return 1
    if ! cp -a -- "$inventory_source/." "$inventory_staging/"; then
        rm -rf -- "$inventory_staging"
        return 1
    fi
    if [ -e "$inventory_target" ] || [ -L "$inventory_target" ]; then
        if [ -d "$inventory_target" ] && [ ! -L "$inventory_target" ] &&
            diff -qr -- "$inventory_staging" "$inventory_target" >/dev/null; then
            rm -rf -- "$inventory_staging"
        else
            rm -rf -- "$inventory_staging"
            return 1
        fi
    elif ! mv -- "$inventory_staging" "$inventory_target"; then
        rm -rf -- "$inventory_staging"
        return 1
    fi

    if [ -f "$guide_target" ] && [ ! -L "$guide_target" ] &&
        cmp -s -- "$guide_source" "$guide_target"; then
        return 0
    fi
    [ ! -d "$guide_target" ] || return 1
    guide_staging=$(mktemp "$restore_directory/.README.XXXXXX") || return 1
    if ! cp -- "$guide_source" "$guide_staging" ||
        ! mv -fT -- "$guide_staging" "$guide_target"; then
        rm -f -- "$guide_staging"
        return 1
    fi
}

transport_publish_metadata() {
    transport_call publish_metadata
}

backup_publish_metadata_ssh() {
    local guide_source="$PROJECT_ROOT/docs/RESTORE.md"
    local remote_inventory="${DESTINATION%/}/backup/manifests/inventory/$TIMESTAMP"
    local remote_guide_temporary="${DESTINATION%/}/backup/restore/.README.$TIMESTAMP.tmp"
    local verification_output

    BACKUP_METADATA_STAGE="metadata validation"
    backup_metadata_id_safe "$TIMESTAMP" || return 1
    [ -d "$INVENTORY_DIR" ] && [ -f "$guide_source" ] || return 1

    BACKUP_METADATA_STAGE="metadata directory preparation"
    {
        printf "backup_id=%q\n" "$TIMESTAMP"
        cat <<'REMOTE_METADATA_PREPARE'
set -eu
case "$backup_id" in *[!A-Za-z0-9._-]*|"") exit 1 ;; esac
mkdir -p "${destination%/}/backup/manifests/inventory/$backup_id"
mkdir -p "${destination%/}/backup/restore"
REMOTE_METADATA_PREPARE
    } | ssh_run_destination_script "$SSH_KEY" "$BACKUP_USER" "$BACKUP_HOST" "$DESTINATION" accept-new || return 1

    BACKUP_METADATA_STAGE="inventory publication"
    rsync -a --protect-args --ignore-existing -e "ssh -i $SSH_KEY -o BatchMode=yes -o StrictHostKeyChecking=accept-new" -- "$INVENTORY_DIR/"         "${BACKUP_USER}@${BACKUP_HOST}:$remote_inventory/" >/dev/null || return 1
    verification_output=$(rsync -aicn --delete --protect-args -e "ssh -i $SSH_KEY -o BatchMode=yes -o StrictHostKeyChecking=accept-new" -- "$INVENTORY_DIR/"         "${BACKUP_USER}@${BACKUP_HOST}:$remote_inventory/") || return 1
    [ -z "$verification_output" ] || return 1

    BACKUP_METADATA_STAGE="recovery guide publication"
    rsync -a --protect-args -e "ssh -i $SSH_KEY -o BatchMode=yes -o StrictHostKeyChecking=accept-new" -- "$guide_source" \
        "${BACKUP_USER}@${BACKUP_HOST}:$remote_guide_temporary" >/dev/null || return 1
    {
        printf "backup_id=%q\n" "$TIMESTAMP"
        cat <<'REMOTE_METADATA_GUIDE'
set -eu
case "$backup_id" in *[!A-Za-z0-9._-]*|"") exit 1 ;; esac
restore_directory="${destination%/}/backup/restore"
temporary="$restore_directory/.README.$backup_id.tmp"
target="$restore_directory/README.md"
[ -f "$temporary" ] && [ ! -L "$temporary" ] || exit 1
if [ -f "$target" ] && [ ! -L "$target" ] && cmp -s -- "$temporary" "$target"; then
    rm -f -- "$temporary"
else
    [ ! -d "$target" ] || exit 1
    mv -f -- "$temporary" "$target"
fi
REMOTE_METADATA_GUIDE
    } | ssh_run_destination_script "$SSH_KEY" "$BACKUP_USER" "$BACKUP_HOST" "$DESTINATION" accept-new || return 1
    # shellcheck disable=SC2034 # Consumed by backup status reporting.
    BACKUP_METADATA_STAGE=""
}

run_backup_metadata_hook() {
    local rsync_exit_code="$1"
    local publisher="${2:-transport_publish_metadata}"
    if ! backup_rsync_copy_usable "$rsync_exit_code"; then BACKUP_METADATA_STATUS="skipped"; return 0; fi
    if "$publisher"; then BACKUP_METADATA_STATUS="success"; return 0; fi
    # shellcheck disable=SC2034 # Consumed by backup orchestration and tests.
    BACKUP_METADATA_STATUS="failed"
    return 1
}
