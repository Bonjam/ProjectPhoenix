#!/bin/bash

retention_resolve_count() {
    local configured_value="${1:-}"

    RETENTION_COUNT_DEFAULTED="no"
    if [[ "$configured_value" =~ ^[1-9][0-9]*$ ]]; then
        RETENTION_COUNT="$configured_value"
    else
        RETENTION_COUNT=5
        RETENTION_COUNT_DEFAULTED="yes"
    fi
}

retention_analyse_directory() {
    local directory="$1"
    local retention_count="$2"
    local entry
    local entry_name
    local eligible_count
    local retained_start
    local size
    local -a timestamped_files=()

    RETENTION_DIRECTORY_EXISTS="no"
    RETENTION_TIMESTAMPED_COUNT=0
    RETENTION_TOTAL_BYTES=0
    RETENTION_NEWEST="none"
    RETENTION_OLDEST="none"
    RETENTION_RETAINED=0
    RETENTION_ELIGIBLE=0
    RETENTION_ELIGIBLE_BYTES=0
    RETENTION_ELIGIBLE_FILES=()
    RETENTION_LATEST_STATUS="missing"
    RETENTION_LATEST_MATCHES="not applicable"
    RETENTION_SUSPICIOUS_COUNT=0

    [ -d "$directory" ] || return 0
    [ -r "$directory" ] && [ -x "$directory" ] || return 2
    RETENTION_DIRECTORY_EXISTS="yes"

    while IFS= read -r -d "" entry; do
        entry_name="${entry##*/}"
        if [[ "$entry_name" =~ ^integrity-[0-9]{8}-[0-9]{6}\.txt$ ]] &&
            [ -f "$entry" ] && [ ! -L "$entry" ]; then
            timestamped_files+=("$entry_name")
            size=$(stat -c "%s" -- "$entry") || return 2
            RETENTION_TOTAL_BYTES=$((RETENTION_TOTAL_BYTES + size))
        else
            RETENTION_SUSPICIOUS_COUNT=$((RETENTION_SUSPICIOUS_COUNT + 1))
        fi
    done < <(
        find "$directory" -mindepth 1 -maxdepth 1 \
            -name "integrity-*.txt" -print0 2>/dev/null |
            LC_ALL=C sort -z
    )

    RETENTION_TIMESTAMPED_COUNT=${#timestamped_files[@]}
    if [ "$RETENTION_TIMESTAMPED_COUNT" -ne 0 ]; then
        RETENTION_OLDEST="${timestamped_files[0]}"
        RETENTION_NEWEST="${timestamped_files[$((RETENTION_TIMESTAMPED_COUNT - 1))]}"
    fi

    if [ "$RETENTION_TIMESTAMPED_COUNT" -le "$retention_count" ]; then
        RETENTION_RETAINED="$RETENTION_TIMESTAMPED_COUNT"
    else
        RETENTION_RETAINED="$retention_count"
        eligible_count=$((RETENTION_TIMESTAMPED_COUNT - retention_count))
        RETENTION_ELIGIBLE="$eligible_count"
        retained_start="$eligible_count"
        RETENTION_ELIGIBLE_FILES=("${timestamped_files[@]:0:retained_start}")
        for entry_name in "${RETENTION_ELIGIBLE_FILES[@]}"; do
            size=$(stat -c "%s" -- "$directory/$entry_name") || return 2
            RETENTION_ELIGIBLE_BYTES=$((RETENTION_ELIGIBLE_BYTES + size))
        done
    fi

    if [ -L "$directory/latest.txt" ]; then
        RETENTION_LATEST_STATUS="symlink"
    elif [ -f "$directory/latest.txt" ]; then
        RETENTION_LATEST_STATUS="regular file"
        if [ "$RETENTION_TIMESTAMPED_COUNT" -ne 0 ]; then
            if cmp -s -- "$directory/latest.txt" "$directory/$RETENTION_NEWEST"; then
                RETENTION_LATEST_MATCHES="yes"
            else
                RETENTION_LATEST_MATCHES="no"
            fi
        fi
    fi
}

retention_emit_analysis() {
    printf "directory_exists=%s\n" "$RETENTION_DIRECTORY_EXISTS"
    printf "timestamped_count=%s\n" "$RETENTION_TIMESTAMPED_COUNT"
    printf "total_bytes=%s\n" "$RETENTION_TOTAL_BYTES"
    printf "newest=%s\n" "$RETENTION_NEWEST"
    printf "oldest=%s\n" "$RETENTION_OLDEST"
    printf "retained=%s\n" "$RETENTION_RETAINED"
    printf "eligible=%s\n" "$RETENTION_ELIGIBLE"
    printf "eligible_bytes=%s\n" "$RETENTION_ELIGIBLE_BYTES"
    printf "latest_status=%s\n" "$RETENTION_LATEST_STATUS"
    printf "latest_matches=%s\n" "$RETENTION_LATEST_MATCHES"
    printf "suspicious_count=%s\n" "$RETENTION_SUSPICIOUS_COUNT"
    printf "eligible_file=%s\n" "${RETENTION_ELIGIBLE_FILES[@]}"
}

retention_parse_analysis() {
    local analysis="$1"
    local key
    local value

    RETENTION_ELIGIBLE_FILES=()
    RETENTION_DIRECTORY_EXISTS=""
    RETENTION_TIMESTAMPED_COUNT=""
    RETENTION_TOTAL_BYTES=""
    RETENTION_NEWEST=""
    RETENTION_OLDEST=""
    RETENTION_RETAINED=""
    RETENTION_ELIGIBLE=""
    RETENTION_ELIGIBLE_BYTES=""
    RETENTION_LATEST_STATUS=""
    RETENTION_LATEST_MATCHES=""
    RETENTION_SUSPICIOUS_COUNT=""

    while IFS="=" read -r key value; do
        case "$key" in
            directory_exists) RETENTION_DIRECTORY_EXISTS="$value" ;;
            timestamped_count) RETENTION_TIMESTAMPED_COUNT="$value" ;;
            total_bytes) RETENTION_TOTAL_BYTES="$value" ;;
            newest) RETENTION_NEWEST="$value" ;;
            oldest) RETENTION_OLDEST="$value" ;;
            retained) RETENTION_RETAINED="$value" ;;
            eligible) RETENTION_ELIGIBLE="$value" ;;
            eligible_bytes) RETENTION_ELIGIBLE_BYTES="$value" ;;
            latest_status) RETENTION_LATEST_STATUS="$value" ;;
            latest_matches) RETENTION_LATEST_MATCHES="$value" ;;
            suspicious_count) RETENTION_SUSPICIOUS_COUNT="$value" ;;
            eligible_file) [ -n "$value" ] && RETENTION_ELIGIBLE_FILES+=("$value") ;;
        esac
    done <<< "$analysis"

    [[ "$RETENTION_DIRECTORY_EXISTS" =~ ^(yes|no)$ ]] &&
        [[ "$RETENTION_TIMESTAMPED_COUNT" =~ ^[0-9]+$ ]] &&
        [[ "$RETENTION_TOTAL_BYTES" =~ ^[0-9]+$ ]] &&
        [[ "$RETENTION_RETAINED" =~ ^[0-9]+$ ]] &&
        [[ "$RETENTION_ELIGIBLE" =~ ^[0-9]+$ ]] &&
        [[ "$RETENTION_ELIGIBLE_BYTES" =~ ^[0-9]+$ ]] &&
        [[ "$RETENTION_SUSPICIOUS_COUNT" =~ ^[0-9]+$ ]] &&
        [[ "$RETENTION_LATEST_STATUS" =~ ^(missing|symlink|regular\ file)$ ]] &&
        [[ "$RETENTION_LATEST_MATCHES" =~ ^(yes|no|not\ applicable)$ ]]
}

retention_analysis_has_warning() {
    [ "$RETENTION_DIRECTORY_EXISTS" != "yes" ] ||
        [ "$RETENTION_LATEST_STATUS" != "regular file" ] ||
        { [ "$RETENTION_TIMESTAMPED_COUNT" -ne 0 ] &&
            [ "$RETENTION_LATEST_MATCHES" != "yes" ]; } ||
        [ "$RETENTION_SUSPICIOUS_COUNT" -ne 0 ]
}

retention_report_area() {
    local heading="$1"
    local directory="$2"

    echo
    echo "$heading"
    printf "%*s\n" "${#heading}" "" | tr " " "-"
    printf "%-21s: %s\n" "Directory" "$directory"
    printf "%-21s: %s\n" "Timestamped Files" "$RETENTION_TIMESTAMPED_COUNT"
    printf "%-21s: %s bytes\n" "Total Size" "$RETENTION_TOTAL_BYTES"
    printf "%-21s: %s\n" "Newest" "$RETENTION_NEWEST"
    printf "%-21s: %s\n" "Oldest" "$RETENTION_OLDEST"
    printf "%-21s: %s\n" "Retained" "$RETENTION_RETAINED"
    printf "%-21s: %s\n" "Eligible for Cleanup" "$RETENTION_ELIGIBLE"
    printf "%-21s: %s bytes\n" "Eligible Bytes" "$RETENTION_ELIGIBLE_BYTES"
    printf "%-21s: %s\n" "latest.txt" "$RETENTION_LATEST_STATUS"
    printf "%-21s: %s\n" "Latest Matches Newest" "$RETENTION_LATEST_MATCHES"
    printf "%-21s: %s\n" "Suspicious Names" "$RETENTION_SUSPICIOUS_COUNT"
    if [ "${#RETENTION_ELIGIBLE_FILES[@]}" -ne 0 ]; then
        echo
        echo "Eligible for future cleanup"
        echo "---------------------------"
        printf "%s\n" "${RETENTION_ELIGIBLE_FILES[@]}" | head -n 25
    fi
}

retention_remote_analysis() {
    {
        printf "retention_count=%q\n" "$RETENTION_COUNT"
        cat <<\REMOTE_RETENTION
set -u
directory="${destination%/}/backup/manifests/integrity"
if [ ! -d "$directory" ]; then
    printf "directory_exists=no\ntimestamped_count=0\ntotal_bytes=0\nnewest=none\noldest=none\nretained=0\neligible=0\neligible_bytes=0\nlatest_status=missing\nlatest_matches=not applicable\nsuspicious_count=0\n"
    exit 0
fi
[ -r "$directory" ] && [ -x "$directory" ] || exit 2
mapfile -d "" -t entries < <(find "$directory" -mindepth 1 -maxdepth 1 -name "integrity-*.txt" -print0 2>/dev/null | LC_ALL=C sort -z)
timestamped=()
total_bytes=0
suspicious=0
for entry in "${entries[@]}"; do
    name=${entry##*/}
    if [[ "$name" =~ ^integrity-[0-9]{8}-[0-9]{6}\.txt$ ]] && [ -f "$entry" ] && [ ! -L "$entry" ]; then
        timestamped+=("$name")
        size=$(stat -c "%s" -- "$entry") || exit 2
        total_bytes=$((total_bytes + size))
    else
        suspicious=$((suspicious + 1))
    fi
done
count=${#timestamped[@]}
newest=none
oldest=none
retained=$count
eligible=0
eligible_bytes=0
if [ "$count" -ne 0 ]; then
    oldest=${timestamped[0]}
    newest=${timestamped[$((count - 1))]}
fi
if [ "$count" -gt "$retention_count" ]; then
    retained=$retention_count
    eligible=$((count - retention_count))
    for name in "${timestamped[@]:0:eligible}"; do
        size=$(stat -c "%s" -- "$directory/$name") || exit 2
        eligible_bytes=$((eligible_bytes + size))
    done
fi
latest_status=missing
latest_matches="not applicable"
if [ -L "$directory/latest.txt" ]; then
    latest_status=symlink
elif [ -f "$directory/latest.txt" ]; then
    latest_status="regular file"
    if [ "$count" -ne 0 ]; then
        if cmp -s -- "$directory/latest.txt" "$directory/$newest"; then latest_matches=yes; else latest_matches=no; fi
    fi
fi
printf "directory_exists=yes\ntimestamped_count=%s\ntotal_bytes=%s\nnewest=%s\noldest=%s\nretained=%s\neligible=%s\neligible_bytes=%s\nlatest_status=%s\nlatest_matches=%s\nsuspicious_count=%s\n" \
    "$count" "$total_bytes" "$newest" "$oldest" "$retained" "$eligible" "$eligible_bytes" "$latest_status" "$latest_matches" "$suspicious"
if [ "$eligible" -ne 0 ]; then printf "eligible_file=%s\n" "${timestamped[@]:0:eligible}"; fi
REMOTE_RETENTION
    } | ssh_run_read_only_destination_script \
        "$SSH_KEY" "$BACKUP_USER" "$BACKUP_HOST" "$DESTINATION" \
        accept-new bash
}

run_integrity_retention() {
    local analysis
    local retention_status="PASS"

    validate_config || return 1
    section "PROJECT PHOENIX INTEGRITY RETENTION"
    integrity_manifest_root_safe "$MANIFEST_DIR" "$PROJECT_ROOT" || {
        log_error "MANIFEST_DIR is unsafe or outside PROJECT_ROOT"
        return 1
    }
    retention_resolve_count "${INTEGRITY_RETENTION_COUNT:-}"
    printf "Retention Count: %s\n" "$RETENTION_COUNT"
    if [ "$RETENTION_COUNT_DEFAULTED" = "yes" ]; then
        log_warning "Invalid or missing retention count; defaulting to 5"
        retention_status="WARNING"
    fi

    retention_analyse_directory "$MANIFEST_DIR/integrity" "$RETENTION_COUNT" || return 1
    retention_report_area "Local Generated Manifests" "$MANIFEST_DIR/integrity"
    retention_analysis_has_warning && retention_status="WARNING"

    retention_analyse_directory "$MANIFEST_DIR/integrity/remote" "$RETENTION_COUNT" || return 1
    retention_report_area "Copied Remote References" "$MANIFEST_DIR/integrity/remote"
    retention_analysis_has_warning && retention_status="WARNING"

    ssh_key_exists "$SSH_KEY" || { log_error "Configured SSH key file does not exist"; return 1; }
    ssh_test_connection "$SSH_KEY" "$BACKUP_USER" "$BACKUP_HOST" accept-new || { log_error "SSH connection failed"; return 1; }
    analysis=$(retention_remote_analysis) || { log_error "Remote retention analysis failed"; return 1; }
    retention_parse_analysis "$analysis" || { log_error "Malformed remote retention output"; return 1; }
    retention_report_area "Raspberry Pi References" "${DESTINATION%/}/backup/manifests/integrity"
    retention_analysis_has_warning && retention_status="WARNING"

    echo
    echo "RETENTION STATUS: $retention_status"
    echo
    echo "Read-only analysis only."
    echo "No files were deleted."
}
