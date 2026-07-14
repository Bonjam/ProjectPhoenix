#!/bin/bash

transport_local_default_allowed_roots() {
    printf "%s\n" "/mnt/c:/mnt/d:/mnt/e:/mnt/f:/tmp"
}

transport_local_configure() {
    DESTINATION_PATH="${DESTINATION_PATH:-${DESTINATION:-}}"
    DESTINATION="$DESTINATION_PATH"
    LOCAL_ALLOWED_ROOTS="${LOCAL_ALLOWED_ROOTS:-$(transport_local_default_allowed_roots)}"
}

transport_local_path_has_unsafe_characters() {
    [[ "$1" == *$'\n'* || "$1" == *$'\r'* || "$1" == *$'\t'* ]] ||
        [[ "$1" =~ [[:cntrl:]] ]]
}

transport_local_path_has_traversal() {
    case "/$1/" in */../*|*/./*) return 0 ;; *) return 1 ;; esac
}

transport_local_path_within() {
    local candidate="${1%/}" root="${2%/}"
    [ -n "$candidate" ] || candidate="/"
    [ -n "$root" ] || root="/"
    case "$candidate" in "$root"|"$root"/*) return 0 ;; *) return 1 ;; esac
}

transport_local_existing_components_safe() {
    local path="$1" current="" component
    local -a components=()
    IFS=/ read -r -a components <<< "${path#/}"
    for component in "${components[@]}"; do
        [ -n "$component" ] || continue
        current="$current/$component"
        [ ! -L "$current" ] || return 1
    done
}

transport_local_allowed_root() {
    local path="$1" roots="${2:-${LOCAL_ALLOWED_ROOTS:-$(transport_local_default_allowed_roots)}}"
    local root resolved_root
    local -a allowed=()
    IFS=: read -r -a allowed <<< "$roots"
    [ "${#allowed[@]}" -ne 0 ] || return 1
    for root in "${allowed[@]}"; do
        if [ -z "$root" ] || [[ "$root" != /* ]]; then continue; fi
        transport_local_path_has_unsafe_characters "$root" && continue
        resolved_root=$(readlink -m -- "$root") || continue
        [ "$path" != "$resolved_root" ] || continue
        case "$path" in "$resolved_root"/*) return 0 ;; esac
    done
    return 1
}

transport_local_validate_path() {
    local destination_path="${1:-${DESTINATION_PATH:-}}"
    local source_path="${2:-${SOURCE:-}}"
    local project_root="${3:-${PROJECT_ROOT:-}}"
    local allowed_roots="${4:-${LOCAL_ALLOWED_ROOTS:-$(transport_local_default_allowed_roots)}}"
    local resolved_destination resolved_source resolved_project

    LOCAL_PATH_ERROR=""
    if [ -z "$destination_path" ]; then LOCAL_PATH_ERROR="destination path is empty"; return 1; fi
    if transport_local_path_has_unsafe_characters "$destination_path"; then LOCAL_PATH_ERROR="destination path contains unsafe control characters"; return 1; fi
    if [[ "$destination_path" != /* ]]; then LOCAL_PATH_ERROR="destination path must be absolute"; return 1; fi
    if transport_local_path_has_traversal "$destination_path"; then LOCAL_PATH_ERROR="destination path contains traversal components"; return 1; fi
    resolved_destination=$(readlink -m -- "$destination_path") || { LOCAL_PATH_ERROR="destination path cannot be resolved"; return 1; }
    if [ "$resolved_destination" = / ]; then LOCAL_PATH_ERROR="destination path cannot be /"; return 1; fi
    transport_local_allowed_root "$resolved_destination" "$allowed_roots" || { LOCAL_PATH_ERROR="destination path is outside LOCAL_ALLOWED_ROOTS"; return 1; }
    transport_local_existing_components_safe "$destination_path" || { LOCAL_PATH_ERROR="destination path contains an existing symlink component"; return 1; }

    if [ -n "$source_path" ]; then
        [[ "$source_path" == /* ]] || { LOCAL_PATH_ERROR="SOURCE must be absolute"; return 1; }
        resolved_source=$(readlink -m -- "$source_path") || return 1
        if transport_local_path_within "$resolved_destination" "$resolved_source" ||
            transport_local_path_within "$resolved_source" "$resolved_destination"; then
            LOCAL_PATH_ERROR="SOURCE and destination must not overlap"
            return 1
        fi
    fi
    if [ -n "$project_root" ]; then
        resolved_project=$(readlink -m -- "$project_root") || return 1
        if [ "$resolved_destination" = "$resolved_project" ] ||
            transport_local_path_within "$resolved_project" "$resolved_destination"; then
            LOCAL_PATH_ERROR="destination cannot equal or contain PROJECT_ROOT"
            return 1
        fi
    fi
    # shellcheck disable=SC2034 # Exposed to provider callers and lightweight tests.
    LOCAL_RESOLVED_DESTINATION="$resolved_destination"
}

transport_local_validate_config() {
    transport_config_value_present "${DESTINATION_PATH:-}" &&
        transport_local_validate_path "$DESTINATION_PATH" "${SOURCE:-}" "${PROJECT_ROOT:-}" \
            "${LOCAL_ALLOWED_ROOTS:-$(transport_local_default_allowed_roots)}"
}

transport_local_inspect_config() {
    transport_local_validate_config
}

transport_local_inspection_path() {
    local path="$1"
    while [ ! -e "$path" ] && [ ! -L "$path" ] && [ "$path" != / ]; do
        path=$(dirname -- "$path")
    done
    printf "%s\n" "$path"
}

transport_local_filesystem_id() {
    local inspection_path
    inspection_path=$(transport_local_inspection_path "$DESTINATION_PATH") || return 1
    if discovery_has_command findmnt; then
        findmnt -n -o FSTYPE -T "$inspection_path" 2>/dev/null | head -n 1
    else
        stat -f -c %T -- "$inspection_path" 2>/dev/null
    fi
}

transport_local_is_wsl_mount() {
    local filesystem_type="${1:-$(transport_local_filesystem_id)}"
    case "$DESTINATION_PATH" in
        /mnt/[a-zA-Z]/*)
            case "$filesystem_type" in 9p|drvfs|wslfs|fuse.*) return 0 ;; esac
            ;;
    esac
    return 1
}

transport_local_filesystem_label() {
    local filesystem_type="${1:-$(transport_local_filesystem_id)}"
    if transport_local_is_wsl_mount "$filesystem_type"; then
        printf "%s\n" "Windows-mounted local filesystem"
    else
        printf "%s\n" "Local filesystem"
    fi
}

transport_local_readiness() {
    local parent filesystem_type df_output
    transport_local_validate_config || return 1
    parent=$(dirname -- "$DESTINATION_PATH")
    LOCAL_PARENT_EXISTS=no
    LOCAL_PARENT_ACCESSIBLE=no
    LOCAL_DESTINATION_EXISTS=no
    LOCAL_DESTINATION_READABLE=no
    LOCAL_DESTINATION_WRITABLE=no
    [ -d "$parent" ] && [ ! -L "$parent" ] && LOCAL_PARENT_EXISTS=yes
    [ "$LOCAL_PARENT_EXISTS" = yes ] && [ -r "$parent" ] && [ -x "$parent" ] && LOCAL_PARENT_ACCESSIBLE=yes
    if [ -d "$DESTINATION_PATH" ] && [ ! -L "$DESTINATION_PATH" ]; then
        LOCAL_DESTINATION_EXISTS=yes
        [ -r "$DESTINATION_PATH" ] && [ -x "$DESTINATION_PATH" ] && LOCAL_DESTINATION_READABLE=yes
        [ -w "$DESTINATION_PATH" ] && [ -x "$DESTINATION_PATH" ] && LOCAL_DESTINATION_WRITABLE=yes
    elif [ "$LOCAL_PARENT_EXISTS" = yes ] && [ -w "$parent" ] && [ -x "$parent" ]; then
        LOCAL_DESTINATION_WRITABLE=yes
    fi
    filesystem_type=$(transport_local_filesystem_id)
    LOCAL_FILESYSTEM_TYPE="${filesystem_type:-unknown}"
    LOCAL_FILESYSTEM_LABEL=$(transport_local_filesystem_label "$LOCAL_FILESYSTEM_TYPE")
    if transport_local_is_wsl_mount "$LOCAL_FILESYSTEM_TYPE"; then LOCAL_WSL_MOUNT=yes; else LOCAL_WSL_MOUNT=no; fi
    LOCAL_AVAILABLE_KB="unavailable"
    LOCAL_USAGE_PERCENT="unavailable"
    df_output=$(df -Pk -- "$(transport_local_inspection_path "$DESTINATION_PATH")" 2>/dev/null | awk 'NR == 2 { gsub(/%/, "", $5); print $4 " " $5 }') || true
    if [[ "$df_output" =~ ^([0-9]+)[[:space:]]+([0-9]+)$ ]]; then
        LOCAL_AVAILABLE_KB=${BASH_REMATCH[1]}
        # shellcheck disable=SC2034 # Consumed by local health reporting.
        LOCAL_USAGE_PERCENT=${BASH_REMATCH[2]}
    fi
}

transport_local_endpoint_summary() {
    printf "%s\n" "${DESTINATION_PATH:-not-set}"
}

transport_local_filesystem_summary() {
    transport_local_filesystem_label
}

transport_local_info() {
    local filesystem_type
    filesystem_type=$(transport_local_filesystem_id)
    printf "%-22s: %s\n" "Path" "${DESTINATION_PATH:-not set}"
    printf "%-22s: %s\n" "Filesystem Type" "$(transport_local_filesystem_label "$filesystem_type")"
    if transport_local_is_wsl_mount "$filesystem_type"; then
        printf "%-22s: yes\n" "WSL Mount"
    else
        printf "%-22s: no\n" "WSL Mount"
    fi
}

transport_local_requirements() {
    discovery_has_command rsync && transport_local_validate_config
}

transport_local_backup_prepare() {
    local parent
    transport_local_validate_config || return 1
    parent=$(dirname -- "$DESTINATION_PATH")
    [ -d "$parent" ] && [ ! -L "$parent" ] && [ -w "$parent" ] && [ -x "$parent" ] || return 1
    if [ -e "$DESTINATION_PATH" ] || [ -L "$DESTINATION_PATH" ]; then
        [ -d "$DESTINATION_PATH" ] && [ ! -L "$DESTINATION_PATH" ] &&
            [ -w "$DESTINATION_PATH" ] && [ -x "$DESTINATION_PATH" ]
    else
        mkdir -- "$DESTINATION_PATH"
    fi
}

transport_local_backup_transfer() {
    rsync -avh --stats --human-readable --exclude-from="$EXCLUDE_FILE" \
        "${SOURCE%/}/" "${DESTINATION_PATH%/}/"
}

transport_local_publish_metadata() {
    BACKUP_METADATA_STAGE="local metadata publication"
    # shellcheck disable=SC2153 # TIMESTAMP is initialised by backup orchestration.
    backup_publish_metadata_local "$INVENTORY_DIR" "$PROJECT_ROOT/docs/RESTORE.md" \
        "${DESTINATION_PATH%/}/backup" "$TIMESTAMP" || return 1
    # shellcheck disable=SC2034 # Consumed by backup status reporting.
    BACKUP_METADATA_STAGE=""
}

transport_local_destination_size() {
    du -sh -- "$DESTINATION_PATH" 2>/dev/null | awk '{print $1}'
}

transport_local_generate_integrity_reference() {
    local timestamp reference_name temporary_manifest destination_directory
    discovery_has_command sha256sum || return 1
    transport_local_restore_preflight || return 1
    timestamp=$(date +%Y%m%d-%H%M%S)
    reference_name="integrity-$timestamp.txt"
    INTEGRITY_TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/project-phoenix-local-integrity.XXXXXX") || return 1
    integrity_register_temp_cleanup || return 1
    temporary_manifest="$INTEGRITY_TEMP_DIR/$reference_name"
    integrity_generate_destination_manifest "$DESTINATION_PATH" "$temporary_manifest" \
        "$(date -Iseconds)" "$reference_name" || return 1
    destination_directory="${DESTINATION_PATH%/}/backup/manifests/integrity"
    integrity_publish_reference_directory "$temporary_manifest" "$reference_name" "$destination_directory" || return 1
    integrity_store_local_remote_reference "$temporary_manifest" "$reference_name" "$DESTINATION_MANIFEST_DIR" || return 1
    # shellcheck disable=SC2034 # Consumed by backup metadata and reporting.
    INTEGRITY_REMOTE_REFERENCE_NAME="$reference_name"
    rm -rf -- "$INTEGRITY_TEMP_DIR"
    integrity_unregister_temp_cleanup
}

transport_local_integrity_fetch_preflight() {
    transport_local_restore_preflight &&
        [ -f "${DESTINATION_PATH%/}/backup/manifests/integrity/latest.txt" ] &&
        [ ! -L "${DESTINATION_PATH%/}/backup/manifests/integrity/latest.txt" ]
}

transport_local_download_integrity_reference() {
    local source="${DESTINATION_PATH%/}/backup/manifests/integrity/latest.txt"
    local output_file="$1"
    [ -f "$source" ] && [ ! -L "$source" ] || return 1
    cp -- "$source" "$output_file"
}

transport_local_integrity_directory() {
    printf "%s\n" "${DESTINATION_PATH%/}/backup/manifests/integrity"
}

transport_local_retention_preflight() {
    transport_local_restore_preflight
}

transport_local_retention_analysis() {
    retention_analyse_directory "$(transport_local_integrity_directory)" "$RETENTION_COUNT" || return 1
    retention_emit_analysis
}

transport_local_retention_delete() {
    local expected_name="$1" directory bytes filename
    local -n expected_ref="$expected_name"
    directory=$(transport_local_integrity_directory) || return 1
    bytes=$(retention_eligible_bytes "$directory" "${expected_ref[@]}") || return 1
    retention_delete_local_eligible "$directory" "$RETENTION_COUNT" "$expected_name" || return 1
    for filename in "${expected_ref[@]}"; do printf "deleted=%s\n" "$filename"; done
    printf "removed=%s\nreclaimed_bytes=%s\n" "$RETENTION_REMOVED_COUNT" "$bytes"
}

transport_local_recovery_preflight() {
    transport_local_restore_preflight
}

transport_local_recovery_analysis() {
    recovery_analyse_local_directory "$DESTINATION_PATH"
}

transport_local_restore_preflight() {
    transport_local_validate_config && [ -d "$DESTINATION_PATH" ] &&
        [ ! -L "$DESTINATION_PATH" ] && [ -r "$DESTINATION_PATH" ] && [ -x "$DESTINATION_PATH" ]
}

transport_local_restore_source_summary() {
    restore_normalize_directory "$DESTINATION_PATH"
}

transport_local_restore_preview_command() {
    printf 'rsync -avh %q %q\n' "${DESTINATION_PATH%/}/" "${SOURCE%/}/"
}

transport_local_restore_dry_run() {
    rsync -avhn --stats "$(restore_normalize_directory "$DESTINATION_PATH")" \
        "$(restore_normalize_directory "$SOURCE")"
}

transport_local_restore_confirmed() {
    rsync -avh --stats "$(restore_normalize_directory "$DESTINATION_PATH")" \
        "$(restore_normalize_directory "$SOURCE")"
}

transport_local_run_health() {
    local failures=0 warnings=0 final_status integrity_directory
    health_resolve_thresholds
    retention_resolve_count "${INTEGRITY_RETENTION_COUNT:-}"
    destination_select_history_file
    destination_select_backup_manifest_directory
    destination_select_integrity_remote_directory
    health_print_heading "Configuration"
    printf "%-22s: PASS\n" "Status"
    printf "%-22s: %s\n" "Destination ID" "$DESTINATION_ID"
    printf "%-22s: %s\n" "Destination Name" "$DESTINATION_NAME"
    printf "%-22s: local\n" "Transport"
    printf "%-22s: %s\n" "Source" "$SOURCE"

    health_print_heading "Local Destination"
    if ! transport_local_readiness; then
        printf "%-22s: FAIL\n" "Path Safety"
        printf "%-22s: %s\n" "Reason" "${LOCAL_PATH_ERROR:-validation failed}"
        echo
        echo "HEALTH STATUS: FAILED"
        return 1
    fi
    printf "%-22s: %s\n" "Path" "$DESTINATION_PATH"
    printf "%-22s: %s\n" "Exists" "$LOCAL_DESTINATION_EXISTS"
    printf "%-22s: %s\n" "Readable" "$([ "$LOCAL_DESTINATION_READABLE" = yes ] && printf PASS || printf FAIL)"
    printf "%-22s: %s\n" "Writable" "$([ "$LOCAL_DESTINATION_WRITABLE" = yes ] && printf PASS || printf FAIL)"
    printf "%-22s: %s\n" "Filesystem" "$LOCAL_FILESYSTEM_LABEL ($LOCAL_FILESYSTEM_TYPE)"
    printf "%-22s: %s%%\n" "Filesystem Usage" "$LOCAL_USAGE_PERCENT"
    printf "%-22s: %s KB\n" "Available Space" "$LOCAL_AVAILABLE_KB"
    [ "$LOCAL_DESTINATION_EXISTS" = yes ] || failures=$((failures + 1))
    [ "$LOCAL_DESTINATION_READABLE" = yes ] || failures=$((failures + 1))
    [ "$LOCAL_DESTINATION_WRITABLE" = yes ] || failures=$((failures + 1))

    health_print_heading "Destination-specific State"
    health_latest_backup_state "$DESTINATION_SELECTED_HISTORY_FILE" "$DESTINATION_SELECTED_BACKUP_MANIFEST_DIR"
    printf "%-22s: %s\n" "Latest Backup" "$HEALTH_BACKUP_STATUS"
    printf "%-22s: %s\n" "Backup Timestamp" "$HEALTH_BACKUP_TIMESTAMP"
    integrity_directory="$DESTINATION_SELECTED_INTEGRITY_REMOTE_DIR"
    if [ -d "$integrity_directory" ] && [ ! -L "$integrity_directory" ] &&
        health_local_integrity_state "$integrity_directory"; then
        printf "%-22s: %s\n" "Integrity Reference" "$HEALTH_LOCAL_REFERENCE"
        [ "$HEALTH_LOCAL_LATEST_MATCHES" != no ] || warnings=$((warnings + 1))
    else
        printf "%-22s: not available\n" "Integrity Reference"
        warnings=$((warnings + 1))
    fi
    if ! health_required_commands_available; then failures=$((failures + 1)); fi
    final_status=$(health_final_status "$failures" "$warnings")
    echo
    echo "HEALTH STATUS: $final_status"
    echo "No files or directories were created."
    [ "$failures" -eq 0 ]
}

run_local_check() {
    local failures=0 warnings=0 final_status
    load_config || return 1
    section "PROJECT PHOENIX LOCAL DESTINATION CHECK"
    if [ "$DESTINATION_TRANSPORT" != local ]; then
        log_error "local-check applies only to DESTINATION_TRANSPORT=local"
        echo "LOCAL CHECK: FAIL"
        return 1
    fi
    if ! transport_local_readiness; then
        log_error "Local destination path is unsafe: ${LOCAL_PATH_ERROR:-validation failed}"
        echo "LOCAL CHECK: FAIL"
        return 1
    fi
    printf "%-24s: %s\n" "Path" "$DESTINATION_PATH"
    printf "%-24s: PASS\n" "Allowed Root"
    printf "%-24s: PASS\n" "Path Overlap"
    printf "%-24s: %s\n" "Parent Exists" "$LOCAL_PARENT_EXISTS"
    printf "%-24s: %s\n" "Destination Exists" "$LOCAL_DESTINATION_EXISTS"
    printf "%-24s: %s\n" "Readable" "$LOCAL_DESTINATION_READABLE"
    printf "%-24s: %s\n" "Apparent Writability" "$LOCAL_DESTINATION_WRITABLE"
    printf "%-24s: %s\n" "Filesystem Type" "$LOCAL_FILESYSTEM_LABEL"
    printf "%-24s: %s\n" "WSL Mount" "$LOCAL_WSL_MOUNT"
    printf "%-24s: %s KB\n" "Available Space" "$LOCAL_AVAILABLE_KB"
    if discovery_has_command rsync; then printf "%-24s: PASS\n" "rsync"; else printf "%-24s: FAIL\n" "rsync"; failures=$((failures + 1)); fi
    [ "$LOCAL_PARENT_EXISTS" = yes ] && [ "$LOCAL_PARENT_ACCESSIBLE" = yes ] || failures=$((failures + 1))
    if [ "$LOCAL_DESTINATION_EXISTS" = yes ]; then
        [ "$LOCAL_DESTINATION_READABLE" = yes ] && [ "$LOCAL_DESTINATION_WRITABLE" = yes ] || failures=$((failures + 1))
    else
        warnings=$((warnings + 1))
    fi
    if [ "$failures" -ne 0 ]; then final_status=FAIL; elif [ "$warnings" -ne 0 ]; then final_status=WARNING; else final_status=PASS; fi
    echo
    echo "LOCAL CHECK: $final_status"
    echo "No files or directories were created."
    [ "$failures" -eq 0 ]
}

transport_register local transport_local
