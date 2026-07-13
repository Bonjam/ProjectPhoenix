#!/bin/bash

# Destination-state migration is local and copy-first. These arrays contain
# only validated relative paths selected by the latest read-only analysis.
declare -ga MIGRATION_AREA_KEYS=(history integrity status reports)
declare -gA MIGRATION_SOURCE_PATH=()
declare -gA MIGRATION_TARGET_PATH=()
declare -gA MIGRATION_SOURCE_PRESENT=()
declare -gA MIGRATION_TARGET_PRESENT=()
declare -gA MIGRATION_SOURCE_FILES=()
declare -gA MIGRATION_TARGET_FILES=()
declare -gA MIGRATION_SOURCE_BYTES=()
declare -gA MIGRATION_IDENTICAL_FILES=()
declare -gA MIGRATION_ELIGIBLE_FILES=()
declare -gA MIGRATION_ELIGIBLE_BYTES=()
declare -gA MIGRATION_CONFLICTS=()
declare -gA MIGRATION_ACTION=()
declare -ga MIGRATION_FILES_HISTORY=()
declare -ga MIGRATION_FILES_INTEGRITY=()
declare -ga MIGRATION_FILES_STATUS=()
declare -ga MIGRATION_FILES_REPORTS=()
declare -ga MIGRATION_CONFLICT_MESSAGES=()

migration_files_array_name() {
    case "$1" in
        history) printf "MIGRATION_FILES_HISTORY\n" ;;
        integrity) printf "MIGRATION_FILES_INTEGRITY\n" ;;
        status) printf "MIGRATION_FILES_STATUS\n" ;;
        reports) printf "MIGRATION_FILES_REPORTS\n" ;;
        *) return 1 ;;
    esac
}

migration_area_paths() {
    case "$1" in
        history)
            MIGRATION_CURRENT_SOURCE="$HISTORY_DIR"
            MIGRATION_CURRENT_TARGET="$DESTINATION_HISTORY_DIR"
            ;;
        integrity)
            MIGRATION_CURRENT_SOURCE="$MANIFEST_DIR/integrity/remote"
            MIGRATION_CURRENT_TARGET="$DESTINATION_INTEGRITY_REMOTE_DIR"
            ;;
        status)
            MIGRATION_CURRENT_SOURCE="$STATUS_DIR"
            MIGRATION_CURRENT_TARGET="$DESTINATION_STATUS_DIR"
            ;;
        reports)
            MIGRATION_CURRENT_SOURCE="$REPORT_DIR"
            MIGRATION_CURRENT_TARGET="$DESTINATION_REPORT_DIR"
            ;;
        *) return 1 ;;
    esac
}

migration_relative_path_supported() {
    local relative_path="$1"
    [ -n "$relative_path" ] &&
        [[ "$relative_path" != /* && "$relative_path" != *$'\n'* && "$relative_path" != *$'\t'* ]] &&
        case "/$relative_path/" in */../*|*/./*) return 1 ;; *) return 0 ;; esac
}

migration_reset_analysis() {
    local area
    MIGRATION_TOTAL_SOURCE_FILES=0
    MIGRATION_TOTAL_SOURCE_BYTES=0
    MIGRATION_TOTAL_IDENTICAL=0
    MIGRATION_TOTAL_ELIGIBLE=0
    MIGRATION_TOTAL_CONFLICTS=0
    MIGRATION_CONFLICT_MESSAGES=()
    # shellcheck disable=SC2034 # Arrays are populated and consumed through namerefs.
    MIGRATION_FILES_HISTORY=()
    # shellcheck disable=SC2034 # Arrays are populated and consumed through namerefs.
    MIGRATION_FILES_INTEGRITY=()
    # shellcheck disable=SC2034 # Arrays are populated and consumed through namerefs.
    MIGRATION_FILES_STATUS=()
    # shellcheck disable=SC2034 # Arrays are populated and consumed through namerefs.
    MIGRATION_FILES_REPORTS=()
    for area in "${MIGRATION_AREA_KEYS[@]}"; do
        MIGRATION_SOURCE_PRESENT["$area"]="absent"
        MIGRATION_TARGET_PRESENT["$area"]="absent"
        MIGRATION_SOURCE_FILES["$area"]=0
        MIGRATION_TARGET_FILES["$area"]=0
        MIGRATION_SOURCE_BYTES["$area"]=0
        MIGRATION_IDENTICAL_FILES["$area"]=0
        MIGRATION_ELIGIBLE_FILES["$area"]=0
        MIGRATION_ELIGIBLE_BYTES["$area"]=0
        MIGRATION_CONFLICTS["$area"]=0
        MIGRATION_ACTION["$area"]="nothing to do"
    done
}

migration_record_conflict() {
    local area="$1" message="$2"
    MIGRATION_CONFLICTS["$area"]=$((MIGRATION_CONFLICTS["$area"] + 1))
    MIGRATION_TOTAL_CONFLICTS=$((MIGRATION_TOTAL_CONFLICTS + 1))
    MIGRATION_CONFLICT_MESSAGES+=("$area: $message")
}

migration_count_target_files() {
    local area="$1" target="$2" entry relative
    local count=0
    local -a entries=()

    [ -e "$target" ] || [ -L "$target" ] || return 0
    if [ -L "$target" ] || [ ! -d "$target" ]; then
        migration_record_conflict "$area" "target root is not a safe regular directory"
        return 0
    fi
    shopt -s dotglob nullglob globstar
    entries=("$target"/**)
    shopt -u dotglob nullglob globstar
    for entry in "${entries[@]}"; do
        [ "$entry" != "$target" ] || continue
        relative=${entry#"$target"/}
        [ -n "$relative" ] || continue
        if [ -L "$entry" ]; then
            migration_record_conflict "$area" "target contains symlink: $relative"
        elif [ -f "$entry" ]; then
            count=$((count + 1))
        elif [ ! -d "$entry" ]; then
            migration_record_conflict "$area" "target contains unsupported entry: $relative"
        fi
    done
    MIGRATION_TARGET_FILES["$area"]="$count"
}

migration_analyse_area() {
    local area="$1" source target entry relative size array_name
    local source_count=0 source_bytes=0 identical=0 eligible=0 eligible_bytes=0
    local -a entries=()
    local -n eligible_ref

    migration_area_paths "$area" || return 1
    source="$MIGRATION_CURRENT_SOURCE"
    target="$MIGRATION_CURRENT_TARGET"
    MIGRATION_SOURCE_PATH["$area"]="$source"
    MIGRATION_TARGET_PATH["$area"]="$target"
    array_name=$(migration_files_array_name "$area") || return 1
    # shellcheck disable=SC2178 # The variable becomes a nameref to the selected area array.
    declare -n eligible_ref="$array_name"

    destination_path_components_safe "$source" "$PROJECT_ROOT" || {
        migration_record_conflict "$area" "legacy source path is unsafe or escapes PROJECT_ROOT"
        return 0
    }
    destination_path_beneath_project "$target" "$PROJECT_ROOT" || {
        migration_record_conflict "$area" "target escapes PROJECT_ROOT"
        return 0
    }
    if [ -e "$target" ] || [ -L "$target" ]; then
        MIGRATION_TARGET_PRESENT["$area"]="present"
    fi
    migration_count_target_files "$area" "$target"

    if [ ! -e "$source" ] && [ ! -L "$source" ]; then
        return 0
    fi
    MIGRATION_SOURCE_PRESENT["$area"]="present"
    if [ -L "$source" ] || [ ! -d "$source" ]; then
        migration_record_conflict "$area" "legacy source root is not a safe regular directory"
        return 0
    fi

    shopt -s dotglob nullglob globstar
    entries=("$source"/**)
    shopt -u dotglob nullglob globstar
    for entry in "${entries[@]}"; do
        [ "$entry" != "$source" ] || continue
        relative=${entry#"$source"/}
        [ -n "$relative" ] || continue
        if [ "$area" != integrity ] &&
            { [ "$relative" = destinations ] || [[ "$relative" == destinations/* ]]; }; then
            continue
        fi
        if ! migration_relative_path_supported "$relative"; then
            migration_record_conflict "$area" "unsupported relative path"
            continue
        fi
        if [ -L "$entry" ]; then
            migration_record_conflict "$area" "legacy source contains symlink: $relative"
            continue
        fi
        if [ -d "$entry" ]; then
            if [ "$area" = integrity ]; then
                migration_record_conflict "$area" "unexpected directory: $relative"
            fi
            continue
        fi
        if [ ! -f "$entry" ]; then
            migration_record_conflict "$area" "legacy source contains unsupported entry: $relative"
            continue
        fi
        if [ "$area" = integrity ] && [ "$relative" != latest.txt ] &&
            [[ ! "$relative" =~ ^integrity-[0-9]{8}-[0-9]{6}\.txt$ ]]; then
            migration_record_conflict "$area" "unexpected integrity filename: $relative"
            continue
        fi

        source_count=$((source_count + 1))
        size=$(stat -c "%s" -- "$entry") || {
            migration_record_conflict "$area" "cannot inspect source file: $relative"
            continue
        }
        source_bytes=$((source_bytes + size))
        if [ -L "$target/$relative" ]; then
            migration_record_conflict "$area" "target is a symlink: $relative"
        elif [ -e "$target/$relative" ]; then
            if [ -f "$target/$relative" ] && cmp -s -- "$entry" "$target/$relative"; then
                identical=$((identical + 1))
            else
                migration_record_conflict "$area" "target differs or has an unsafe type: $relative"
            fi
        else
            eligible_ref+=("$relative")
            eligible=$((eligible + 1))
            eligible_bytes=$((eligible_bytes + size))
        fi
    done

    MIGRATION_SOURCE_FILES["$area"]="$source_count"
    MIGRATION_SOURCE_BYTES["$area"]="$source_bytes"
    MIGRATION_IDENTICAL_FILES["$area"]="$identical"
    MIGRATION_ELIGIBLE_FILES["$area"]="$eligible"
    MIGRATION_ELIGIBLE_BYTES["$area"]="$eligible_bytes"
    MIGRATION_TOTAL_SOURCE_FILES=$((MIGRATION_TOTAL_SOURCE_FILES + source_count))
    MIGRATION_TOTAL_SOURCE_BYTES=$((MIGRATION_TOTAL_SOURCE_BYTES + source_bytes))
    MIGRATION_TOTAL_IDENTICAL=$((MIGRATION_TOTAL_IDENTICAL + identical))
    MIGRATION_TOTAL_ELIGIBLE=$((MIGRATION_TOTAL_ELIGIBLE + eligible))
}

migration_integrity_validate_latest() {
    local source="${MIGRATION_SOURCE_PATH[integrity]}"
    local target="${MIGRATION_TARGET_PATH[integrity]}"
    local source_latest="$source/latest.txt" target_latest="$target/latest.txt"
    local name source_newest="" target_newest=""
    local -a source_timestamped=() target_timestamped=()

    [ "${MIGRATION_SOURCE_PRESENT[integrity]}" = present ] || return 0
    if [ -d "$source" ] && [ ! -L "$source" ]; then
        shopt -s nullglob
        source_timestamped=("$source"/integrity-????????-??????.txt)
        shopt -u nullglob
    fi
    for name in "${source_timestamped[@]}"; do
        [[ "${name##*/}" =~ ^integrity-[0-9]{8}-[0-9]{6}\.txt$ ]] || continue
        if [ ! -f "$name" ] || [ -L "$name" ]; then continue; fi
        source_newest="$name"
    done
    if [ -n "$source_newest" ]; then
        if [ ! -f "$source_latest" ] || [ -L "$source_latest" ] ||
            ! cmp -s -- "$source_latest" "$source_newest"; then
            migration_record_conflict integrity "legacy latest.txt does not match its newest timestamped reference"
        fi
    elif [ -e "$source_latest" ] || [ -L "$source_latest" ]; then
        migration_record_conflict integrity "legacy latest.txt has no timestamped reference"
    fi

    if [ -d "$target" ] && [ ! -L "$target" ]; then
        shopt -s nullglob
        target_timestamped=("$target"/integrity-????????-??????.txt)
        shopt -u nullglob
    fi
    for name in "${target_timestamped[@]}"; do
        [[ "${name##*/}" =~ ^integrity-[0-9]{8}-[0-9]{6}\.txt$ ]] || {
            migration_record_conflict integrity "destination contains an unexpected timestamped reference"
            continue
        }
        if [ ! -f "$name" ] || [ -L "$name" ]; then continue; fi
        target_newest="$name"
    done
    if [ -n "$target_newest" ]; then
        if [ ! -f "$target_latest" ] || [ -L "$target_latest" ] ||
            ! cmp -s -- "$target_latest" "$target_newest"; then
            migration_record_conflict integrity "destination latest.txt does not match its newest timestamped reference"
        fi
        if [ -n "$source_newest" ] && [[ "${target_newest##*/}" > "${source_newest##*/}" ]] &&
            ! cmp -s -- "$source_latest" "$target_newest"; then
            migration_record_conflict integrity "destination has a newer reference than legacy latest.txt"
        fi
    fi
}

migration_finish_area_actions() {
    local area conflicts eligible identical source_files
    for area in "${MIGRATION_AREA_KEYS[@]}"; do
        conflicts=${MIGRATION_CONFLICTS["$area"]}
        eligible=${MIGRATION_ELIGIBLE_FILES["$area"]}
        identical=${MIGRATION_IDENTICAL_FILES["$area"]}
        source_files=${MIGRATION_SOURCE_FILES["$area"]}
        if [ "$conflicts" -ne 0 ]; then
            MIGRATION_ACTION["$area"]="conflict"
        elif [ "$eligible" -ne 0 ]; then
            MIGRATION_ACTION["$area"]="copy $eligible file(s)"
        elif [ "$source_files" -ne 0 ] && [ "$identical" -eq "$source_files" ]; then
            MIGRATION_ACTION["$area"]="already migrated"
        else
            MIGRATION_ACTION["$area"]="nothing to do"
        fi
    done
}

destination_migration_analyse() {
    local area
    migration_reset_analysis
    for area in "${MIGRATION_AREA_KEYS[@]}"; do
        migration_analyse_area "$area" || return 1
    done
    migration_integrity_validate_latest
    migration_finish_area_actions

    if [ "$DESTINATION_ID" = default ]; then
        MIGRATION_ANALYSIS_STATUS="PROFILE REQUIRED"
    elif [ "$MIGRATION_TOTAL_CONFLICTS" -ne 0 ]; then
        MIGRATION_ANALYSIS_STATUS="CONFLICT"
    elif [ "$MIGRATION_TOTAL_ELIGIBLE" -ne 0 ]; then
        MIGRATION_ANALYSIS_STATUS="AVAILABLE"
    else
        MIGRATION_ANALYSIS_STATUS="NOTHING TO DO"
    fi
}

migration_render_area() {
    local area="$1"
    echo
    printf "%s\n" "${area^^}"
    printf "%*s\n" "${#area}" "" | tr " " "-"
    printf "%-24s: %s\n" "Legacy Source" "${MIGRATION_SOURCE_PATH[$area]}"
    printf "%-24s: %s\n" "Destination Target" "${MIGRATION_TARGET_PATH[$area]}"
    printf "%-24s: %s\n" "Source" "${MIGRATION_SOURCE_PRESENT[$area]}"
    printf "%-24s: %s\n" "Target" "${MIGRATION_TARGET_PRESENT[$area]}"
    printf "%-24s: %s\n" "Source Files" "${MIGRATION_SOURCE_FILES[$area]}"
    printf "%-24s: %s\n" "Target Files" "${MIGRATION_TARGET_FILES[$area]}"
    printf "%-24s: %s bytes\n" "Source Size" "${MIGRATION_SOURCE_BYTES[$area]}"
    printf "%-24s: %s\n" "Identical Files" "${MIGRATION_IDENTICAL_FILES[$area]}"
    printf "%-24s: %s\n" "Eligible Files" "${MIGRATION_ELIGIBLE_FILES[$area]}"
    printf "%-24s: %s\n" "Conflicts" "${MIGRATION_CONFLICTS[$area]}"
    printf "%-24s: %s\n" "Proposed Action" "${MIGRATION_ACTION[$area]}"
}

destination_migration_render_analysis() {
    local area
    section "PROJECT PHOENIX DESTINATION MIGRATION ANALYSIS"
    printf "%-24s: %s\n" "Destination ID" "$DESTINATION_ID"
    printf "%-24s: %s\n" "Destination Name" "$DESTINATION_NAME"
    printf "%-24s: %s\n" "Transport" "$DESTINATION_TRANSPORT"
    if [ "$DESTINATION_ID" = default ]; then
        echo
        echo "An explicit non-default destination profile is required."
        echo "Add these values to config.conf before confirmed migration:"
        echo "DESTINATION_ID=pi-usb"
        echo "DESTINATION_NAME=Raspberry Pi USB"
        echo "DESTINATION_TRANSPORT=ssh-rsync"
    fi
    for area in "${MIGRATION_AREA_KEYS[@]}"; do
        migration_render_area "$area"
    done
    if [ "${#MIGRATION_CONFLICT_MESSAGES[@]}" -ne 0 ]; then
        echo
        echo "Conflicts"
        echo "---------"
        printf -- "- %s\n" "${MIGRATION_CONFLICT_MESSAGES[@]}"
    fi
    echo
    printf "%-24s: %s\n" "Total Source Files" "$MIGRATION_TOTAL_SOURCE_FILES"
    printf "%-24s: %s bytes\n" "Total Source Size" "$MIGRATION_TOTAL_SOURCE_BYTES"
    printf "%-24s: %s\n" "Already Identical" "$MIGRATION_TOTAL_IDENTICAL"
    printf "%-24s: %s\n" "Eligible to Copy" "$MIGRATION_TOTAL_ELIGIBLE"
    printf "%-24s: %s\n" "Conflicts" "$MIGRATION_TOTAL_CONFLICTS"
    echo
    echo "MIGRATION STATUS: $MIGRATION_ANALYSIS_STATUS"
    echo
    echo "No files changed."
}

migration_staging_path_safe() {
    local staging_root="$1"
    destination_path_beneath_project "$staging_root" "$PROJECT_ROOT" &&
        [[ "${staging_root##*/}" == .destination-migration-stage.* ]] &&
        [ ! -L "$staging_root" ]
}

destination_migration_cleanup_staging() {
    [ -n "${DESTINATION_MIGRATION_STAGING_ROOT:-}" ] || return 0
    migration_staging_path_safe "$DESTINATION_MIGRATION_STAGING_ROOT" || return 1
    [ ! -e "$DESTINATION_MIGRATION_STAGING_ROOT" ] ||
        rm -rf -- "$DESTINATION_MIGRATION_STAGING_ROOT"
    DESTINATION_MIGRATION_STAGING_ROOT=""
}

migration_register_staging_cleanup() {
    MIGRATION_TRAP_ID="destination-migration-${BASHPID}-${RANDOM}"
    phoenix_trap_register "$MIGRATION_TRAP_ID" \
        "destination_migration_cleanup_staging" EXIT HUP INT TERM
}

migration_unregister_staging_cleanup() {
    [ -n "${MIGRATION_TRAP_ID:-}" ] || return 0
    phoenix_trap_unregister "$MIGRATION_TRAP_ID" EXIT HUP INT TERM
    MIGRATION_TRAP_ID=""
}

migration_relative_parent() {
    if [[ "$1" == */* ]]; then printf "%s\n" "${1%/*}"; else printf ".\n"; fi
}

migration_stage_area() {
    local area="$1" source stage relative array_name size parent
    local staged_count=0 staged_bytes=0
    local -n files_ref
    migration_area_paths "$area" || return 1
    source="$MIGRATION_CURRENT_SOURCE"
    stage="$DESTINATION_MIGRATION_STAGING_ROOT/$area"
    array_name=$(migration_files_array_name "$area") || return 1
    # shellcheck disable=SC2178 # The variable becomes a nameref to the selected area array.
    declare -n files_ref="$array_name"
    [ "${#files_ref[@]}" -ne 0 ] || return 0
    mkdir -p -- "$stage" || return 1
    for relative in "${files_ref[@]}"; do
        migration_relative_path_supported "$relative" || return 1
        [ -f "$source/$relative" ] && [ ! -L "$source/$relative" ] || return 1
        parent=$(migration_relative_parent "$relative") || return 1
        mkdir -p -- "$stage/$parent" || return 1
        cp -p -- "$source/$relative" "$stage/$relative" || return 1
        cmp -s -- "$source/$relative" "$stage/$relative" || return 1
        size=$(stat -c "%s" -- "$stage/$relative") || return 1
        staged_count=$((staged_count + 1))
        staged_bytes=$((staged_bytes + size))
    done
    [ "$staged_count" -eq "${MIGRATION_ELIGIBLE_FILES[$area]}" ] || return 1
    [ "$staged_bytes" -eq "${MIGRATION_ELIGIBLE_BYTES[$area]}" ] || return 1
}

migration_publish_area() {
    local area="$1" target stage relative array_name parent temporary
    local -n files_ref
    migration_area_paths "$area" || return 1
    target="$MIGRATION_CURRENT_TARGET"
    stage="$DESTINATION_MIGRATION_STAGING_ROOT/$area"
    array_name=$(migration_files_array_name "$area") || return 1
    # shellcheck disable=SC2178 # Nameref selects the current area's file list.
    declare -n files_ref="$array_name"
    [ "${#files_ref[@]}" -ne 0 ] || return 0

    destination_prepare_directory "$target" || return 1
    for relative in "${files_ref[@]}"; do
        parent=$(migration_relative_parent "$relative") || return 1
        parent="$target/$parent"
        destination_prepare_directory "$parent" || return 1
        if [ -e "$target/$relative" ] || [ -L "$target/$relative" ]; then
            [ -f "$target/$relative" ] && [ ! -L "$target/$relative" ] &&
                cmp -s -- "$stage/$relative" "$target/$relative" || return 1
            continue
        fi
        temporary=$(mktemp "$parent/.migration-copy.XXXXXX") || return 1
        if ! cp -p -- "$stage/$relative" "$temporary" ||
            ! cmp -s -- "$stage/$relative" "$temporary"; then
            rm -f -- "$temporary"
            return 1
        fi
        if ! ln -- "$temporary" "$target/$relative" 2>/dev/null; then
            rm -f -- "$temporary"
            [ -f "$target/$relative" ] && [ ! -L "$target/$relative" ] &&
                cmp -s -- "$stage/$relative" "$target/$relative" || return 1
        else
            rm -f -- "$temporary"
        fi
        migration_log "Copied file: $area/$relative"
    done
}

migration_verify_area() {
    local area="$1" source target relative array_name
    local -n files_ref
    migration_area_paths "$area" || return 1
    source="$MIGRATION_CURRENT_SOURCE"
    target="$MIGRATION_CURRENT_TARGET"
    array_name=$(migration_files_array_name "$area") || return 1
    # shellcheck disable=SC2178 # The variable becomes a nameref to the selected area array.
    declare -n files_ref="$array_name"
    for relative in "${files_ref[@]}"; do
        [ -f "$target/$relative" ] && [ ! -L "$target/$relative" ] &&
            cmp -s -- "$source/$relative" "$target/$relative" || return 1
    done
}

migration_log_open() {
    destination_path_components_safe "$LOG_DIR" "$PROJECT_ROOT" || return 1
    mkdir -p -- "$LOG_DIR" || return 1
    MIGRATION_LOG_FILE=$(mktemp "$LOG_DIR/destination-migration-$DESTINATION_ID-$(date +%Y%m%d-%H%M%S).XXXXXX.log") || return 1
}

migration_log() {
    [ -n "${MIGRATION_LOG_FILE:-}" ] || return 0
    printf "%s\n" "$*" >> "$MIGRATION_LOG_FILE"
}

migration_write_history() {
    local status="$1" details="$2" history_file
    destination_prepare_directory "$DESTINATION_HISTORY_DIR" || return 1
    history_file="$DESTINATION_HISTORY_DIR/migration.log"
    [ ! -L "$history_file" ] || return 1
    printf "%s | destination-migrate | %s | %s; destination_id=%q; destination_name=%q; transport=%q\n" \
        "$(date +"%Y-%m-%d %H:%M:%S")" "$status" "$details" \
        "$DESTINATION_ID" "$DESTINATION_NAME" "$DESTINATION_TRANSPORT" >> "$history_file"
}

migration_write_marker() {
    local marker_directory marker_file temporary area
    marker_directory="$DESTINATION_STATUS_DIR/migration"
    destination_prepare_directory "$marker_directory" || return 1
    marker_file="$marker_directory/migration-$(date +%Y%m%d-%H%M%S).txt"
    [ ! -e "$marker_file" ] && [ ! -L "$marker_file" ] || return 1
    temporary=$(mktemp "$marker_directory/.migration-marker.XXXXXX") || return 1
    {
        echo "destination_id=$DESTINATION_ID"
        echo "destination_name=$DESTINATION_NAME"
        echo "transport=$DESTINATION_TRANSPORT"
        echo "migrated_at=$(date -Iseconds)"
        for area in "${MIGRATION_AREA_KEYS[@]}"; do
            printf "%s_source=%s\n" "$area" "${MIGRATION_SOURCE_PATH[$area]}"
            printf "%s_target=%s\n" "$area" "${MIGRATION_TARGET_PATH[$area]}"
            printf "%s_files=%s\n" "$area" "${MIGRATION_SOURCE_FILES[$area]}"
        done
        echo "verification=passed"
        echo "legacy_retained=yes"
    } > "$temporary"
    if ! mv -- "$temporary" "$marker_file"; then
        rm -f -- "$temporary"
        return 1
    fi
    MIGRATION_MARKER_FILE="$marker_file"
}

migration_confirmation_matches() {
    [ "$1" = "MIGRATE LEGACY STATE TO $DESTINATION_ID" ]
}

migration_record_noncomplete() {
    local status="$1" details="$2"
    migration_log "Final status: $status"
    migration_write_history "${status,,}" "$details" || true
    echo
    echo "MIGRATION STATUS: $status"
}

run_destination_migration() {
    load_config || return 1
    destination_migration_analyse || return 1
    destination_migration_render_analysis
}

run_destination_migrate() {
    local area confirmation

    load_config || return 1
    destination_migration_analyse || return 1
    if [ "$DESTINATION_ID" = default ]; then
        destination_migration_render_analysis
        return 1
    fi
    migration_log_open || {
        log_error "Unable to create the local destination migration log"
        return 1
    }
    destination_migration_render_analysis | tee -a "$MIGRATION_LOG_FILE"

    case "$MIGRATION_ANALYSIS_STATUS" in
        "NOTHING TO DO")
            migration_record_noncomplete "NOTHING TO DO" "No eligible legacy state"
            return 0
            ;;
        CONFLICT)
            migration_record_noncomplete CONFLICT "Migration analysis found conflicts"
            return 1
            ;;
        AVAILABLE) ;;
        *)
            migration_record_noncomplete FAILED "Unexpected migration analysis status"
            return 1
            ;;
    esac

    echo
    echo "Type exactly: MIGRATE LEGACY STATE TO $DESTINATION_ID"
    read -r confirmation
    if ! migration_confirmation_matches "$confirmation"; then
        migration_log "Confirmation: cancelled"
        migration_record_noncomplete CANCELLED "Confirmation was not accepted"
        return 2
    fi
    migration_log "Confirmation: accepted"

    DESTINATION_MIGRATION_STAGING_ROOT=$(mktemp -d \
        "$PROJECT_ROOT/.destination-migration-stage.XXXXXX") || {
        migration_record_noncomplete FAILED "Unable to create staging directory"
        return 1
    }
    migration_register_staging_cleanup || {
        destination_migration_cleanup_staging || true
        migration_record_noncomplete FAILED "Unable to register staging cleanup"
        return 1
    }

    for area in "${MIGRATION_AREA_KEYS[@]}"; do
        [ "${MIGRATION_ELIGIBLE_FILES[$area]}" -ne 0 ] || continue
        migration_log "Staging area: $area"
        if ! migration_stage_area "$area"; then
            migration_log "Failed area: $area (staging)"
            destination_migration_cleanup_staging || true
            migration_unregister_staging_cleanup
            migration_record_noncomplete FAILED "Staging failed for $area"
            return 1
        fi
    done
    for area in "${MIGRATION_AREA_KEYS[@]}"; do
        [ "${MIGRATION_ELIGIBLE_FILES[$area]}" -ne 0 ] || continue
        migration_log "Publishing area: $area"
        if ! migration_publish_area "$area" || ! migration_verify_area "$area"; then
            migration_log "Failed area: $area (publication or verification)"
            destination_migration_cleanup_staging || true
            migration_unregister_staging_cleanup
            migration_record_noncomplete FAILED "Publication or verification failed for $area"
            return 1
        fi
        migration_log "Verified area: $area"
    done
    if ! migration_write_marker; then
        destination_migration_cleanup_staging || true
        migration_unregister_staging_cleanup
        migration_record_noncomplete FAILED "Migration marker publication failed"
        return 1
    fi
    destination_migration_cleanup_staging || true
    migration_unregister_staging_cleanup
    migration_log "Marker: $MIGRATION_MARKER_FILE"
    migration_log "Legacy retained: yes"
    migration_log "Final status: COMPLETE"
    if ! migration_write_history completed "Legacy state copied and verified; legacy retained=yes"; then
        migration_log "History recording failed"
        log_error "Migration data was verified but destination history recording failed"
        echo "Legacy state retained for rollback."
        echo "MIGRATION STATUS: FAILED"
        return 1
    fi
    echo
    log_success "Destination state migration completed"
    echo "Marker: $MIGRATION_MARKER_FILE"
    echo "Legacy state retained for rollback."
    echo "MIGRATION STATUS: COMPLETE"
}
