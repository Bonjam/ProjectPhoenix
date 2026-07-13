#!/bin/bash

destination_error() {
    if declare -F log_error >/dev/null 2>&1; then
        log_error "$1"
    else
        printf "ERROR: %s\n" "$1" >&2
    fi
}

destination_warning() {
    if declare -F log_warning >/dev/null 2>&1; then
        log_warning "$1"
    else
        printf "WARNING: %s\n" "$1" >&2
    fi
}

destination_id_valid() {
    [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,47}$ ]]
}

destination_transport_supported() {
    case "$1" in
        ssh-rsync) return 0 ;;
        *) return 1 ;;
    esac
}

destination_path_beneath_project() {
    local candidate="$1" project_root="$2"
    local resolved_candidate resolved_root

    [ -n "$candidate" ] && [ -n "$project_root" ] || return 1
    resolved_root=$(readlink -m -- "$project_root") || return 1
    resolved_candidate=$(readlink -m -- "$candidate") || return 1
    case "$resolved_candidate" in
        "$resolved_root"/*) return 0 ;;
        *) return 1 ;;
    esac
}

destination_path_components_safe() {
    local candidate="$1" project_root="$2"
    local current relative resolved_candidate resolved_root component
    local -a components=()

    destination_path_beneath_project "$candidate" "$project_root" || return 1
    resolved_root=$(readlink -m -- "$project_root") || return 1
    resolved_candidate=$(readlink -m -- "$candidate") || return 1
    [ ! -L "$resolved_root" ] || return 1
    relative=${resolved_candidate#"$resolved_root"/}
    current="$resolved_root"
    IFS="/" read -r -a components <<< "$relative"
    for component in "${components[@]}"; do
        [ -n "$component" ] || continue
        current="$current/$component"
        [ ! -L "$current" ] || return 1
    done
}

destination_resolve_state_paths() {
    DESTINATION_HISTORY_DIR="$HISTORY_DIR/destinations/$DESTINATION_ID"
    DESTINATION_STATUS_DIR="$STATUS_DIR/destinations/$DESTINATION_ID"
    DESTINATION_REPORT_DIR="$REPORT_DIR/destinations/$DESTINATION_ID"
    DESTINATION_MANIFEST_DIR="$MANIFEST_DIR/destinations/$DESTINATION_ID"
    DESTINATION_INTEGRITY_REMOTE_DIR="$DESTINATION_MANIFEST_DIR/integrity/remote"
    DESTINATION_STATE_NAMESPACE="destinations/$DESTINATION_ID"

    # shellcheck disable=SC2153 # PROJECT_ROOT is initialised by the launcher.
    destination_path_components_safe "$DESTINATION_HISTORY_DIR" "$PROJECT_ROOT" &&
        destination_path_components_safe "$DESTINATION_STATUS_DIR" "$PROJECT_ROOT" &&
        destination_path_components_safe "$DESTINATION_REPORT_DIR" "$PROJECT_ROOT" &&
        destination_path_components_safe "$DESTINATION_MANIFEST_DIR" "$PROJECT_ROOT" &&
        destination_path_components_safe "$DESTINATION_INTEGRITY_REMOTE_DIR" "$PROJECT_ROOT"
}

destination_resolve_context() {
    if [ "${DESTINATION_CONTEXT_RESOLVED:-no}" = "yes" ]; then
        destination_resolve_state_paths
        return
    fi
    if [ -z "${DESTINATION_ID+x}" ] && [ -z "${DESTINATION_NAME+x}" ] &&
        [ -z "${DESTINATION_TRANSPORT+x}" ]; then
        DESTINATION_LEGACY_CONFIGURATION="yes"
    else
        DESTINATION_LEGACY_CONFIGURATION="no"
    fi

    DESTINATION_ID="${DESTINATION_ID:-default}"
    DESTINATION_NAME="${DESTINATION_NAME:-Default Destination}"
    DESTINATION_TRANSPORT="${DESTINATION_TRANSPORT:-ssh-rsync}"

    if ! destination_id_valid "$DESTINATION_ID"; then
        destination_error "DESTINATION_ID must begin with a lowercase letter or digit, contain only lowercase letters, digits, or hyphens, and be at most 48 characters"
        return 1
    fi
    if [ -z "$DESTINATION_NAME" ] || [[ "$DESTINATION_NAME" == *$'\n'* || "$DESTINATION_NAME" == *$'\t'* ]]; then
        destination_error "DESTINATION_NAME must be non-empty and remain on one line"
        return 1
    fi
    if ! destination_transport_supported "$DESTINATION_TRANSPORT"; then
        destination_error "Unsupported DESTINATION_TRANSPORT: $DESTINATION_TRANSPORT (supported: ssh-rsync)"
        return 1
    fi
    DESTINATION_CONTEXT_RESOLVED="yes"
    destination_resolve_state_paths || {
        destination_error "Destination state paths are unsafe or outside PROJECT_ROOT"
        return 1
    }
}

destination_prepare_directory() {
    local directory="$1"
    destination_path_components_safe "$directory" "$PROJECT_ROOT" || return 1
    mkdir -p -- "$directory" || return 1
    destination_path_components_safe "$directory" "$PROJECT_ROOT"
}

destination_select_integrity_remote_directory() {
    local legacy_directory="$MANIFEST_DIR/integrity/remote"

    DESTINATION_INTEGRITY_STATE_SOURCE="namespaced"
    DESTINATION_SELECTED_INTEGRITY_REMOTE_DIR="$DESTINATION_INTEGRITY_REMOTE_DIR"
    if [ -d "$DESTINATION_INTEGRITY_REMOTE_DIR" ] && [ ! -L "$DESTINATION_INTEGRITY_REMOTE_DIR" ]; then
        return 0
    fi
    if [ "$DESTINATION_ID" = "default" ] && [ -d "$legacy_directory" ] && [ ! -L "$legacy_directory" ]; then
        # shellcheck disable=SC2034 # Output consumed by integrity, retention, and health modules.
        DESTINATION_INTEGRITY_STATE_SOURCE="legacy"
        # shellcheck disable=SC2034 # Output consumed by integrity, retention, and health modules.
        DESTINATION_SELECTED_INTEGRITY_REMOTE_DIR="$legacy_directory"
    fi
}

destination_select_history_file() {
    local namespaced_file="$DESTINATION_HISTORY_DIR/history.log"
    local legacy_file="$HISTORY_DIR/history.log"

    DESTINATION_HISTORY_STATE_SOURCE="namespaced"
    DESTINATION_SELECTED_HISTORY_FILE="$namespaced_file"
    if [ -f "$namespaced_file" ] && [ ! -L "$namespaced_file" ]; then
        return 0
    fi
    if [ "$DESTINATION_ID" = "default" ] && [ -f "$legacy_file" ] && [ ! -L "$legacy_file" ]; then
        # shellcheck disable=SC2034 # Output consumed by history and health modules.
        DESTINATION_HISTORY_STATE_SOURCE="legacy"
        # shellcheck disable=SC2034 # Output consumed by history and health modules.
        DESTINATION_SELECTED_HISTORY_FILE="$legacy_file"
    fi
}

destination_select_backup_manifest_directory() {
    DESTINATION_BACKUP_MANIFEST_STATE_SOURCE="namespaced"
    DESTINATION_SELECTED_BACKUP_MANIFEST_DIR="$DESTINATION_MANIFEST_DIR"
    if [ -d "$DESTINATION_MANIFEST_DIR" ]; then
        return 0
    fi
    if [ "$DESTINATION_ID" = "default" ] && [ -d "$MANIFEST_DIR" ]; then
        # shellcheck disable=SC2034 # Output consumed by the health module.
        DESTINATION_BACKUP_MANIFEST_STATE_SOURCE="legacy"
        # shellcheck disable=SC2034 # Output consumed by the health module.
        DESTINATION_SELECTED_BACKUP_MANIFEST_DIR="$MANIFEST_DIR"
    fi
}

destination_endpoint_summary() {
    printf "%s@%s:%s\n" "${BACKUP_USER:-not-set}" "${BACKUP_HOST:-not-set}" "${DESTINATION:-not-set}"
}

destination_state_present() {
    [ -e "$DESTINATION_HISTORY_DIR" ] || [ -e "$DESTINATION_MANIFEST_DIR" ] ||
        [ -e "$DESTINATION_STATUS_DIR" ] || [ -e "$DESTINATION_REPORT_DIR" ]
}

destination_legacy_history_present() {
    [ -f "$HISTORY_DIR/history.log" ] && [ ! -L "$HISTORY_DIR/history.log" ]
}

destination_legacy_integrity_present() {
    [ -d "$MANIFEST_DIR/integrity/remote" ] && [ ! -L "$MANIFEST_DIR/integrity/remote" ]
}

run_destination_info() {
    load_config || return 1
    section "PROJECT PHOENIX DESTINATION"
    printf "%-22s: %s\n" "ID" "$DESTINATION_ID"
    printf "%-22s: %s\n" "Name" "$DESTINATION_NAME"
    printf "%-22s: %s\n" "Transport" "$DESTINATION_TRANSPORT"
    printf "%-22s: %s\n" "Host" "${BACKUP_HOST:-not set}"
    printf "%-22s: %s\n" "User" "${BACKUP_USER:-not set}"
    printf "%-22s: %s\n" "Path" "${DESTINATION:-not set}"
    printf "%-22s: %s/...\n" "State Namespace" "$DESTINATION_STATE_NAMESPACE"
    printf "%-22s: %s\n" "Legacy Configuration" "$DESTINATION_LEGACY_CONFIGURATION"
    echo
    echo "No connection test was performed."
    echo "No files were changed."
}

run_destination_migration() {
    local legacy_history="absent" legacy_integrity="absent" destination_state="absent"
    local migration_status="NOTHING TO DO"

    load_config || return 1
    destination_legacy_history_present && legacy_history="present"
    destination_legacy_integrity_present && legacy_integrity="present"
    destination_state_present && destination_state="present"

    if [ "$DESTINATION_ID" = "default" ] &&
        { [ "$legacy_history" = "present" ] || [ "$legacy_integrity" = "present" ]; }; then
        if [ "$destination_state" = "present" ]; then
            migration_status="CONFLICT"
        else
            migration_status="AVAILABLE"
        fi
    fi

    section "PROJECT PHOENIX DESTINATION MIGRATION ANALYSIS"
    printf "%-30s: %s\n" "Destination ID" "$DESTINATION_ID"
    printf "%-30s: %s\n" "Legacy History" "$legacy_history"
    printf "%-30s: %s\n" "Legacy Integrity References" "$legacy_integrity"
    printf "%-30s: %s\n" "Destination-specific State" "$destination_state"
    printf "%-30s: %s\n" "History Source" "$HISTORY_DIR/history.log"
    printf "%-30s: %s\n" "History Target" "$DESTINATION_HISTORY_DIR/history.log"
    printf "%-30s: %s\n" "Integrity Source" "$MANIFEST_DIR/integrity/remote"
    printf "%-30s: %s\n" "Integrity Target" "$DESTINATION_INTEGRITY_REMOTE_DIR"
    if [ "$DESTINATION_ID" != "default" ] &&
        { [ "$legacy_history" = "present" ] || [ "$legacy_integrity" = "present" ]; }; then
        destination_warning "Legacy state is eligible only for the default destination and will not be used here"
    fi
    echo
    echo "MIGRATION STATUS: $migration_status"
    echo
    echo "Read-only analysis only. No files were changed."
}
