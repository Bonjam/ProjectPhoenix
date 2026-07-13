#!/bin/bash

integrity_cleanup_failure_status() {
    if [ "$1" -eq 0 ]; then printf "FAILED\n"; else printf "PARTIAL\n"; fi
}

integrity_cleanup_confirmation_matches() {
    [ "$1" = "DELETE OLD INTEGRITY MANIFESTS" ]
}

retention_filename_valid() {
    [[ "$1" =~ ^integrity-[0-9]{8}-[0-9]{6}\.txt$ ]]
}

retention_arrays_equal() {
    local -n left_ref="$1"
    local -n right_ref="$2"
    local index
    [ "${#left_ref[@]}" -eq "${#right_ref[@]}" ] || return 1
    for index in "${!left_ref[@]}"; do
        [ "${left_ref[$index]}" = "${right_ref[$index]}" ] || return 1
    done
}

retention_eligible_bytes() {
    local directory="$1"
    shift
    local filename size total=0
    for filename in "$@"; do
        retention_filename_valid "$filename" || return 1
        [ -f "$directory/$filename" ] && [ ! -L "$directory/$filename" ] || return 1
        size=$(stat -c "%s" -- "$directory/$filename") || return 1
        total=$((total + size))
    done
    printf "%s\n" "$total"
}

retention_delete_local_eligible() {
    local directory="$1" retention_count="$2" expected_name="$3" log_file="${4:-}"
    local -n expected_ref="$expected_name"
    local approved_parent target_parent filename size
    local -a current=()

    approved_parent=$(readlink -f -- "$directory") || return 1
    [ "$approved_parent" = "$directory" ] || return 1
    retention_analyse_directory "$directory" "$retention_count" || return 1
    # shellcheck disable=SC2034 # Consumed by retention_arrays_equal through a nameref.
    current=("${RETENTION_ELIGIBLE_FILES[@]}")
    retention_arrays_equal "$expected_name" current || return 3

    RETENTION_REMOVED_COUNT=0
    RETENTION_RECLAIMED_BYTES=0
    for filename in "${expected_ref[@]}"; do
        retention_filename_valid "$filename" || return 1
        target_parent=$(readlink -f -- "$(dirname -- "$directory/$filename")") || return 1
        [ "$target_parent" = "$approved_parent" ] || return 1
        [ -f "$directory/$filename" ] && [ ! -L "$directory/$filename" ] || return 1
        size=$(stat -c "%s" -- "$directory/$filename") || return 1
        rm -- "$directory/$filename" || return 1
        RETENTION_REMOVED_COUNT=$((RETENTION_REMOVED_COUNT + 1))
        RETENTION_RECLAIMED_BYTES=$((RETENTION_RECLAIMED_BYTES + size))
        [ -z "$log_file" ] || printf "Deleted: %s\n" "$filename" >> "$log_file"
    done
}

retention_remote_cleanup_script() {
    local retention_count="$1"
    shift
    local filename

    printf "retention_count=%q\n" "$retention_count"
    printf "approved=("
    for filename in "$@"; do
        retention_filename_valid "$filename" || return 1
        printf " %q" "$filename"
    done
    printf " )\n"
    cat <<'REMOTE_CLEANUP'
set -euo pipefail
directory="${destination%/}/backup/manifests/integrity"
[ -d "$directory" ] && [ -r "$directory" ] && [ -w "$directory" ] && [ -x "$directory" ]
entries=()
shopt -s lastpipe
find "$directory" -mindepth 1 -maxdepth 1 -name "integrity-*.txt" -print0 |
    LC_ALL=C sort -z |
    while IFS= read -r -d "" entry; do entries+=("$entry"); done
eligible=()
for entry in "${entries[@]}"; do
    name=${entry##*/}
    if [[ "$name" =~ ^integrity-[0-9]{8}-[0-9]{6}\.txt$ ]] && [ -f "$entry" ] && [ ! -L "$entry" ]; then
        eligible+=("$name")
    fi
done
if [ "${#eligible[@]}" -gt "$retention_count" ]; then
    eligible=("${eligible[@]:0:${#eligible[@]}-retention_count}")
else
    eligible=()
fi
[ "${#approved[@]}" -eq "${#eligible[@]}" ] || exit 3
for index in "${!approved[@]}"; do
    [ "${approved[$index]}" = "${eligible[$index]}" ] || exit 3
done
removed=0
bytes=0
for name in "${approved[@]}"; do
    [[ "$name" =~ ^integrity-[0-9]{8}-[0-9]{6}\.txt$ ]] || exit 1
    target="$directory/$name"
    [ -f "$target" ] && [ ! -L "$target" ] || exit 1
    size=$(stat -c "%s" -- "$target")
    rm -- "$target"
    printf "deleted=%s\n" "$name"
    removed=$((removed + 1))
    bytes=$((bytes + size))
done
printf "removed=%s\nreclaimed_bytes=%s\n" "$removed" "$bytes"
REMOTE_CLEANUP
}

retention_delete_remote_eligible() {
    local expected_name="$1"
    local -n expected_ref="$expected_name"
    # shellcheck disable=SC2153 # Global set by retention_resolve_count.
    retention_remote_cleanup_script "$RETENTION_COUNT" "${expected_ref[@]}" |
        ssh_run_destination_script "$SSH_KEY" "$BACKUP_USER" "$BACKUP_HOST" "$DESTINATION" accept-new
}

integrity_cleanup_record() {
    local log_file="$1"
    shift
    printf "%s\n" "$*" >> "$log_file"
}

integrity_cleanup_finish() {
    local status="$1" return_code="$2" log_file="$3" history_status="$4" details="$5"
    integrity_cleanup_record "$log_file" "Final status: $history_status"
    write_history_entry "integrity-cleanup" "$history_status" "$details"
    echo
    echo "CLEANUP STATUS: $status"
    return "$return_code"
}

run_integrity_cleanup() {
    local analysis confirmation log_file remote_output area_bytes
    local local_removed=0 copied_removed=0 remote_removed=0 reclaimed=0 any_removed=0
    local -a local_eligible=() copied_eligible=() remote_eligible=()

    validate_config || return 1
    section "PROJECT PHOENIX INTEGRITY CLEANUP"
    integrity_manifest_root_safe "$MANIFEST_DIR" "$PROJECT_ROOT" || {
        log_error "MANIFEST_DIR is unsafe or outside PROJECT_ROOT"
        return 1
    }
    retention_resolve_count "${INTEGRITY_RETENTION_COUNT:-}"
    log_file="$LOG_DIR/integrity-cleanup-$(date +%Y%m%d-%H%M%S).log"
    : > "$log_file" || return 1
    integrity_cleanup_record "$log_file" "Started: $(date '+%Y-%m-%d %H:%M:%S')"
    integrity_cleanup_record "$log_file" "Retention count: $RETENTION_COUNT"
    printf "Retention Count: %s\n" "$RETENTION_COUNT"
    [ "$RETENTION_COUNT_DEFAULTED" = "no" ] ||
        log_warning "Invalid or missing retention count; defaulting to 5"

    retention_analyse_directory "$MANIFEST_DIR/integrity" "$RETENTION_COUNT" || {
        integrity_cleanup_record "$log_file" "Failure: local generated analysis"
        integrity_cleanup_finish FAILED 1 "$log_file" failed "Local generated analysis failed"
        return
    }
    retention_report_area "Local Generated Manifests" "$MANIFEST_DIR/integrity"
    local_eligible=("${RETENTION_ELIGIBLE_FILES[@]}")
    integrity_cleanup_record "$log_file" "Eligible local generated: ${local_eligible[*]:-none}"

    retention_analyse_directory "$MANIFEST_DIR/integrity/remote" "$RETENTION_COUNT" || {
        integrity_cleanup_record "$log_file" "Failure: copied remote analysis"
        integrity_cleanup_finish FAILED 1 "$log_file" failed "Copied remote analysis failed"
        return
    }
    retention_report_area "Copied Remote References" "$MANIFEST_DIR/integrity/remote"
    copied_eligible=("${RETENTION_ELIGIBLE_FILES[@]}")
    integrity_cleanup_record "$log_file" "Eligible copied remote: ${copied_eligible[*]:-none}"

    ssh_key_exists "$SSH_KEY" || {
        integrity_cleanup_record "$log_file" "Failure: SSH key missing"
        integrity_cleanup_finish FAILED 1 "$log_file" failed "SSH key validation failed"
        return
    }
    analysis=$(retention_remote_analysis) || {
        integrity_cleanup_record "$log_file" "Failure: remote analysis"
        integrity_cleanup_finish FAILED 1 "$log_file" failed "Remote analysis failed"
        return
    }
    retention_parse_analysis "$analysis" || {
        integrity_cleanup_record "$log_file" "Failure: malformed remote analysis"
        integrity_cleanup_finish FAILED 1 "$log_file" failed "Malformed remote analysis"
        return
    }
    retention_report_area "Raspberry Pi References" "${DESTINATION%/}/backup/manifests/integrity"
    remote_eligible=("${RETENTION_ELIGIBLE_FILES[@]}")
    integrity_cleanup_record "$log_file" "Eligible Raspberry Pi: ${remote_eligible[*]:-none}"

    if [ "${#local_eligible[@]}" -eq 0 ] && [ "${#copied_eligible[@]}" -eq 0 ] &&
        [ "${#remote_eligible[@]}" -eq 0 ]; then
        integrity_cleanup_finish "NOTHING TO DO" 0 "$log_file" nothing-to-do "No eligible manifests"
        return
    fi

    echo
    echo "Type exactly: DELETE OLD INTEGRITY MANIFESTS"
    read -r confirmation
    if ! integrity_cleanup_confirmation_matches "$confirmation"; then
        integrity_cleanup_record "$log_file" "Confirmation: cancelled"
        integrity_cleanup_finish CANCELLED 2 "$log_file" cancelled "Cleanup cancelled before deletion"
        echo
        echo "No files were deleted."
        return 2
    fi
    integrity_cleanup_record "$log_file" "Confirmation: accepted"

    if [ "${#local_eligible[@]}" -ne 0 ]; then
        area_bytes=$(retention_eligible_bytes "$MANIFEST_DIR/integrity" "${local_eligible[@]}") || area_bytes=0
        if ! retention_delete_local_eligible "$MANIFEST_DIR/integrity" "$RETENTION_COUNT" local_eligible "$log_file"; then
            integrity_cleanup_record "$log_file" "Failure: local generated set changed or validation failed"
            if [ "${RETENTION_REMOVED_COUNT:-0}" -ne 0 ]; then
                integrity_cleanup_finish PARTIAL 1 "$log_file" partial "Local generated cleanup failed after a deletion"
            else
                integrity_cleanup_finish FAILED 1 "$log_file" failed "Local generated cleanup failed before any deletion"
            fi
            return
        fi
        local_removed=$RETENTION_REMOVED_COUNT
        [ "$local_removed" -eq 0 ] || any_removed=1
        reclaimed=$((reclaimed + area_bytes))
    fi

    if [ "${#copied_eligible[@]}" -ne 0 ]; then
        area_bytes=$(retention_eligible_bytes "$MANIFEST_DIR/integrity/remote" "${copied_eligible[@]}") || area_bytes=0
        if ! retention_delete_local_eligible "$MANIFEST_DIR/integrity/remote" "$RETENTION_COUNT" copied_eligible "$log_file"; then
            integrity_cleanup_record "$log_file" "Failure: copied remote set changed or validation failed"
            if [ "$any_removed" -eq 0 ] && [ "${RETENTION_REMOVED_COUNT:-0}" -eq 0 ]; then
                integrity_cleanup_finish FAILED 1 "$log_file" failed "Copied remote cleanup failed before any deletion"
            else
                integrity_cleanup_finish PARTIAL 1 "$log_file" partial "A local cleanup failed after deletion"
            fi
            return
        fi
        copied_removed=$RETENTION_REMOVED_COUNT
        [ "$copied_removed" -eq 0 ] || any_removed=1
        reclaimed=$((reclaimed + area_bytes))
    fi

    if [ "${#remote_eligible[@]}" -ne 0 ]; then
        if ! remote_output=$(retention_delete_remote_eligible remote_eligible); then
            integrity_cleanup_record "$log_file" "Failure: Raspberry Pi cleanup"
            if [ "$any_removed" -eq 0 ]; then
                integrity_cleanup_finish FAILED 1 "$log_file" failed "Raspberry Pi cleanup failed before any deletion"
            else
                integrity_cleanup_finish PARTIAL 1 "$log_file" partial "Local files removed; Raspberry Pi cleanup failed"
            fi
            return
        fi
        while IFS="=" read -r key value; do
            case "$key" in
                deleted) integrity_cleanup_record "$log_file" "Deleted remote: $value" ;;
                removed) [[ "$value" =~ ^[0-9]+$ ]] || return 1; remote_removed="$value" ;;
                reclaimed_bytes) [[ "$value" =~ ^[0-9]+$ ]] || return 1; reclaimed=$((reclaimed + value)) ;;
            esac
        done <<< "$remote_output"
    fi

    integrity_cleanup_record "$log_file" "Removed local generated: $local_removed"
    integrity_cleanup_record "$log_file" "Removed copied remote: $copied_removed"
    integrity_cleanup_record "$log_file" "Removed Raspberry Pi: $remote_removed"
    integrity_cleanup_finish COMPLETE 0 "$log_file" completed \
        "Removed local=$local_removed copied=$copied_removed remote=$remote_removed bytes=$reclaimed"
    echo "Local generated files removed : $local_removed"
    echo "Copied remote files removed   : $copied_removed"
    echo "Raspberry Pi files removed    : $remote_removed"
    echo "Total bytes reclaimed         : $reclaimed"
}
