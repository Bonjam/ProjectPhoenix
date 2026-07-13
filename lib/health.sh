#!/bin/bash

health_positive_integer_or_default() {
    local value="$1" default_value="$2"
    if [[ "$value" =~ ^[1-9][0-9]*$ ]]; then printf "%s\n" "$value"; else printf "%s\n" "$default_value"; fi
}

health_resolve_thresholds() {
    HEALTH_BACKUP_HOURS=$(health_positive_integer_or_default "${HEALTH_BACKUP_WARNING_HOURS:-}" 48)
    HEALTH_INTEGRITY_HOURS=$(health_positive_integer_or_default "${HEALTH_INTEGRITY_WARNING_HOURS:-}" 48)
    HEALTH_USAGE_PERCENT=$(health_positive_integer_or_default "${HEALTH_REMOTE_USAGE_WARNING_PERCENT:-}" 85)
    if [ "$HEALTH_USAGE_PERCENT" -gt 100 ]; then HEALTH_USAGE_PERCENT=85; fi
}

health_timestamp_epoch() {
    date -d "$1" +%s 2>/dev/null
}

health_age_hours() {
    local timestamp="$1" now_epoch="${2:-$(date +%s)}" timestamp_epoch
    timestamp_epoch=$(health_timestamp_epoch "$timestamp") || return 1
    [ "$now_epoch" -ge "$timestamp_epoch" ] || return 1
    printf "%s\n" "$(((now_epoch - timestamp_epoch) / 3600))"
}

health_age_human() {
    local hours="$1"
    if [ "$hours" -lt 24 ]; then
        printf "%s hour%s\n" "$hours" "$([ "$hours" -eq 1 ] || printf s)"
    else
        printf "%s day%s\n" "$((hours / 24))" "$([ "$((hours / 24))" -eq 1 ] || printf s)"
    fi
}

health_age_warns() {
    [ "$1" -ge "$2" ]
}

health_usage_warns() {
    [ "$1" -ge "$2" ]
}

health_source_path_safe() {
    local source="$1" normalized
    [ -n "$source" ] || return 1
    normalized="${source%/}"
    [ -n "$normalized" ] || normalized="/"
    case "$normalized" in
        /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/proc|/root|/run|/sbin|/sys|/tmp|/usr|/var)
            return 1
            ;;
    esac
}

health_config_values_valid() {
    [ -n "${PROJECT_NAME:-}" ] && [ -n "${TAGLINE:-}" ] &&
        [ -n "${SOURCE:-}" ] && [ -n "${DESTINATION:-}" ] &&
        [ -n "${BACKUP_HOST:-}" ] && [ -n "${BACKUP_USER:-}" ] &&
        [ -n "${SSH_KEY:-}" ] && [ -n "${BACKUP_DIR:-}" ]
}

health_rsync_status() {
    if [[ "$1" =~ ^[0-9]+$ ]]; then backup_rsync_copy_status "$1"; else printf "unknown\n"; fi
}

health_latest_backup_state() {
    local history_file="$1" manifest_directory="$2"
    local history_line manifest_file timestamp status exit_code
    local -a fields=()

    HEALTH_BACKUP_STATUS="not available"
    HEALTH_BACKUP_TIMESTAMP="not available"
    HEALTH_BACKUP_EXIT_CODE="not available"
    HEALTH_BACKUP_RSYNC_CLASS="unknown"

    if [ -f "$history_file" ]; then
        history_line=$(awk -F ' \\| ' '$2 == "backup" { line=$0 } END { print line }' "$history_file")
        if [ -n "$history_line" ]; then
            IFS="|" read -r timestamp _ status _ <<< "$history_line"
            timestamp="${timestamp%"${timestamp##*[![:space:]]}"}"
            timestamp="${timestamp#"${timestamp%%[![:space:]]*}"}"
            status="${status%"${status##*[![:space:]]}"}"
            status="${status#"${status%%[![:space:]]*}"}"
            HEALTH_BACKUP_TIMESTAMP="$timestamp"
            HEALTH_BACKUP_STATUS="$status"
        fi
    fi

    mapfile -d "" -t fields < <(
        find "$manifest_directory" -mindepth 1 -maxdepth 1 -type f -name "*.txt" -print0 2>/dev/null |
            LC_ALL=C sort -z
    )
    if [ "${#fields[@]}" -ne 0 ]; then
        manifest_file="${fields[$((${#fields[@]} - 1))]}"
        exit_code=$(sed -n 's/^Exit Code:[[:space:]]*//p' "$manifest_file" | head -n 1)
        if [[ "$exit_code" =~ ^[0-9]+$ ]]; then
            HEALTH_BACKUP_EXIT_CODE="$exit_code"
            HEALTH_BACKUP_RSYNC_CLASS=$(health_rsync_status "$exit_code")
        fi
    fi
}

health_local_integrity_state() {
    local directory="$1"
    retention_analyse_directory "$directory" "$RETENTION_COUNT" || return 1
    HEALTH_LOCAL_REFERENCE="$RETENTION_NEWEST"
    HEALTH_LOCAL_LATEST_MATCHES="$RETENTION_LATEST_MATCHES"
}

health_remote_analysis() {
    {
        printf "retention_count=%q\n" "$RETENTION_COUNT"
        cat <<'REMOTE_HEALTH'
set -euo pipefail
[ -d "$destination" ] || { printf "destination_exists=no\n"; exit 0; }
printf "destination_exists=yes\n"
[ -r "$destination" ] && [ -x "$destination" ] || { printf "destination_readable=no\n"; exit 0; }
printf "destination_readable=yes\n"
LC_ALL=C df -Pk -- "$destination" | awk 'NR == 2 {
    gsub(/%/, "", $5)
    printf "filesystem=%s\nfilesystem_total_kb=%s\nfilesystem_used_kb=%s\nfilesystem_available_kb=%s\nfilesystem_usage=%s\n", $1, $2, $3, $4, $5
}'
backup_size=$(du -sh -- "$destination" 2>/dev/null | awk '{print $1}')
top_level=$(find "$destination" -mindepth 1 -maxdepth 1 -print 2>/dev/null | wc -l)
printf "backup_size=%s\ntop_level_entries=%s\n" "$backup_size" "$top_level"
if [ -f "${destination%/}/backup/restore/README.md" ]; then printf "recovery_guide=yes\n"; else printf "recovery_guide=no\n"; fi
if [ -d "${destination%/}/backup/manifests/inventory" ]; then printf "inventory=yes\n"; else printf "inventory=no\n"; fi
integrity_directory="${destination%/}/backup/manifests/integrity"
if [ -d "$integrity_directory" ]; then printf "integrity_directory=yes\n"; else printf "integrity_directory=no\n"; exit 0; fi
mapfile -d "" -t entries < <(find "$integrity_directory" -mindepth 1 -maxdepth 1 -name "integrity-*.txt" -print0 2>/dev/null | LC_ALL=C sort -z)
timestamped=()
suspicious=0
for entry in "${entries[@]}"; do
    name=${entry##*/}
    if [[ "$name" =~ ^integrity-[0-9]{8}-[0-9]{6}\.txt$ ]] && [ -f "$entry" ] && [ ! -L "$entry" ]; then
        timestamped+=("$name")
    else
        suspicious=$((suspicious + 1))
    fi
done
count=${#timestamped[@]}
newest=none
[ "$count" -eq 0 ] || newest=${timestamped[$((count - 1))]}
latest_status=missing
latest_matches="not applicable"
if [ -L "$integrity_directory/latest.txt" ]; then
    latest_status=symlink
elif [ -f "$integrity_directory/latest.txt" ]; then
    latest_status="regular file"
    if [ "$count" -ne 0 ]; then
        if cmp -s -- "$integrity_directory/latest.txt" "$integrity_directory/$newest"; then latest_matches=yes; else latest_matches=no; fi
    fi
fi
retained=$count
eligible=0
if [ "$count" -gt "$retention_count" ]; then retained=$retention_count; eligible=$((count - retention_count)); fi
printf "integrity_newest=%s\nintegrity_count=%s\nintegrity_retained=%s\nintegrity_eligible=%s\nintegrity_suspicious=%s\nremote_latest_status=%s\nremote_latest_matches=%s\n"     "$newest" "$count" "$retained" "$eligible" "$suspicious" "$latest_status" "$latest_matches"
REMOTE_HEALTH
    } | ssh_run_read_only_destination_script \
        "$SSH_KEY" "$BACKUP_USER" "$BACKUP_HOST" "$DESTINATION" accept-new bash
}

health_parse_remote_analysis() {
    local input="$1" key value
    HEALTH_REMOTE_DESTINATION_EXISTS=""
    HEALTH_REMOTE_DESTINATION_READABLE=""
    HEALTH_REMOTE_FILESYSTEM=""
    HEALTH_REMOTE_TOTAL_KB=""
    HEALTH_REMOTE_USED_KB=""
    HEALTH_REMOTE_AVAILABLE_KB=""
    HEALTH_REMOTE_USAGE=""
    HEALTH_REMOTE_BACKUP_SIZE=""
    HEALTH_REMOTE_TOP_LEVEL=""
    HEALTH_REMOTE_GUIDE=""
    HEALTH_REMOTE_INVENTORY=""
    HEALTH_REMOTE_INTEGRITY_DIRECTORY=""
    HEALTH_REMOTE_INTEGRITY_NEWEST="none"
    HEALTH_REMOTE_INTEGRITY_COUNT=0
    HEALTH_REMOTE_RETAINED=0
    HEALTH_REMOTE_ELIGIBLE=0
    HEALTH_REMOTE_SUSPICIOUS=0
    HEALTH_REMOTE_LATEST_STATUS="missing"
    HEALTH_REMOTE_LATEST_MATCHES="not applicable"

    while IFS="=" read -r key value; do
        case "$key" in
            destination_exists) HEALTH_REMOTE_DESTINATION_EXISTS="$value" ;;
            destination_readable) HEALTH_REMOTE_DESTINATION_READABLE="$value" ;;
            filesystem) HEALTH_REMOTE_FILESYSTEM="$value" ;;
            filesystem_total_kb) HEALTH_REMOTE_TOTAL_KB="$value" ;;
            filesystem_used_kb) HEALTH_REMOTE_USED_KB="$value" ;;
            filesystem_available_kb) HEALTH_REMOTE_AVAILABLE_KB="$value" ;;
            filesystem_usage) HEALTH_REMOTE_USAGE="$value" ;;
            backup_size) HEALTH_REMOTE_BACKUP_SIZE="$value" ;;
            top_level_entries) HEALTH_REMOTE_TOP_LEVEL="$value" ;;
            recovery_guide) HEALTH_REMOTE_GUIDE="$value" ;;
            inventory) HEALTH_REMOTE_INVENTORY="$value" ;;
            integrity_directory) HEALTH_REMOTE_INTEGRITY_DIRECTORY="$value" ;;
            integrity_newest) HEALTH_REMOTE_INTEGRITY_NEWEST="$value" ;;
            integrity_count) HEALTH_REMOTE_INTEGRITY_COUNT="$value" ;;
            integrity_retained) HEALTH_REMOTE_RETAINED="$value" ;;
            integrity_eligible) HEALTH_REMOTE_ELIGIBLE="$value" ;;
            integrity_suspicious) HEALTH_REMOTE_SUSPICIOUS="$value" ;;
            remote_latest_status) HEALTH_REMOTE_LATEST_STATUS="$value" ;;
            remote_latest_matches) HEALTH_REMOTE_LATEST_MATCHES="$value" ;;
        esac
    done <<< "$input"
    [[ "$HEALTH_REMOTE_DESTINATION_EXISTS" =~ ^(yes|no)$ ]] || return 1
    [ "$HEALTH_REMOTE_DESTINATION_EXISTS" = "no" ] && return 0
    [[ "$HEALTH_REMOTE_DESTINATION_READABLE" =~ ^(yes|no)$ ]] || return 1
    [ "$HEALTH_REMOTE_DESTINATION_READABLE" = "no" ] && return 0
    [[ "$HEALTH_REMOTE_USAGE" =~ ^[0-9]+$ ]] &&
        [[ "$HEALTH_REMOTE_TOP_LEVEL" =~ ^[0-9]+$ ]] &&
        [[ "$HEALTH_REMOTE_INTEGRITY_COUNT" =~ ^[0-9]+$ ]] &&
        [[ "$HEALTH_REMOTE_RETAINED" =~ ^[0-9]+$ ]] &&
        [[ "$HEALTH_REMOTE_ELIGIBLE" =~ ^[0-9]+$ ]] &&
        [[ "$HEALTH_REMOTE_SUSPICIOUS" =~ ^[0-9]+$ ]]
}

health_integrity_filename_timestamp() {
    local filename="$1"
    [[ "$filename" =~ ^integrity-([0-9]{8})-([0-9]{6})\.txt$ ]] || return 1
    printf "%s-%s-%s %s:%s:%s\n"         "${BASH_REMATCH[1]:0:4}" "${BASH_REMATCH[1]:4:2}" "${BASH_REMATCH[1]:6:2}"         "${BASH_REMATCH[2]:0:2}" "${BASH_REMATCH[2]:2:2}" "${BASH_REMATCH[2]:4:2}"
}

health_remote_checks_pass() {
    [ "$1" = yes ] && [ "$2" = yes ] && [ "$3" = yes ]
}

health_latest_mismatch_warns() {
    [ "$1" = no ] || [ "$2" = no ] || [ "$3" = no ]
}

health_retention_warns() {
    [ "$1" -ne 0 ]
}

health_required_flags_pass() {
    [ "$1" = yes ] && [ "$2" = yes ] && [ "$3" = yes ] && [ "$4" = yes ]
}

health_required_commands_available() {
    local restore_flag=no dry_run_flag=no confirm_flag=no verify_flag=no
    declare -F run_restore >/dev/null 2>&1 && restore_flag=yes
    declare -F run_restore_dry_run >/dev/null 2>&1 && dry_run_flag=yes
    declare -F run_restore_confirm >/dev/null 2>&1 && confirm_flag=yes
    declare -F run_verify_restore >/dev/null 2>&1 && verify_flag=yes
    health_required_flags_pass "$restore_flag" "$dry_run_flag" "$confirm_flag" "$verify_flag"
}

health_final_status() {
    if [ "$1" -ne 0 ]; then printf "FAILED\n"; elif [ "$2" -ne 0 ]; then printf "WARNING\n"; else printf "PASS\n"; fi
}

health_print_heading() {
    echo
    echo "$1"
    printf "%*s\n" "${#1}" "" | tr " " "-"
}

run_health() {
    local remote_output backup_age_hours integrity_age_hours integrity_timestamp
    local failures=0 warnings=0 final_status
    local -a warning_messages=()

    section "PROJECT PHOENIX HEALTH CHECK"
    if ! load_config_if_exists || ! health_config_values_valid; then
        echo "Configuration is missing or invalid."
        echo
        echo "HEALTH STATUS: FAILED"
        return 2
    fi
    health_resolve_thresholds
    retention_resolve_count "${INTEGRITY_RETENTION_COUNT:-}"

    health_print_heading "Configuration"
    printf "%-22s: PASS\n" "Status"
    printf "%-22s: %s\n" "Source" "$SOURCE"
    printf "%-22s: %s\n" "Destination" "$DESTINATION"
    printf "%-22s: %s\n" "Backup Host" "$BACKUP_HOST"
    printf "%-22s: %s\n" "SSH Key" "$([ -f "$SSH_KEY" ] && [ ! -L "$SSH_KEY" ] && printf PASS || printf FAIL)"
    printf "%-22s: %s\n" "Retention Count" "$RETENTION_COUNT"
    if [ ! -f "$SSH_KEY" ] || [ -L "$SSH_KEY" ]; then failures=$((failures + 1)); fi
    if ! health_source_path_safe "$SOURCE"; then failures=$((failures + 1)); fi

    health_print_heading "Raspberry Pi"
    if [ "$failures" -eq 0 ] && ssh_test_connection "$SSH_KEY" "$BACKUP_USER" "$BACKUP_HOST" accept-new; then
        printf "%-22s: PASS\n" "SSH Connectivity"
        if remote_output=$(health_remote_analysis 2>/dev/null) &&
            health_parse_remote_analysis "$remote_output"; then
            if [ "$HEALTH_REMOTE_DESTINATION_EXISTS" != "yes" ] || [ "$HEALTH_REMOTE_DESTINATION_READABLE" != "yes" ]; then
                printf "%-22s: FAIL\n" "Destination Readable"
                failures=$((failures + 1))
            else
                printf "%-22s: PASS\n" "Destination Readable"
                printf "%-22s: %s\n" "Filesystem" "$HEALTH_REMOTE_FILESYSTEM"
                printf "%-22s: %s%%\n" "Filesystem Usage" "$HEALTH_REMOTE_USAGE"
                printf "%-22s: %s KB\n" "Available Space" "$HEALTH_REMOTE_AVAILABLE_KB"
                printf "%-22s: %s KB\n" "Used Space" "$HEALTH_REMOTE_USED_KB"
                printf "%-22s: %s KB\n" "Total Space" "$HEALTH_REMOTE_TOTAL_KB"
                if health_usage_warns "$HEALTH_REMOTE_USAGE" "$HEALTH_USAGE_PERCENT"; then
                    warnings=$((warnings + 1)); warning_messages+=("Remote filesystem usage is high.")
                fi
            fi
        else
            printf "%-22s: FAIL\n" "Destination Readable"
            failures=$((failures + 1))
        fi
    else
        printf "%-22s: FAIL\n" "SSH Connectivity"
        failures=$((failures + 1))
    fi

    health_latest_backup_state "$HISTORY_DIR/history.log" "$MANIFEST_DIR"
    health_print_heading "Latest Backup"
    printf "%-22s: %s\n" "Status" "$HEALTH_BACKUP_STATUS"
    printf "%-22s: %s\n" "Timestamp" "$HEALTH_BACKUP_TIMESTAMP"
    if backup_age_hours=$(health_age_hours "$HEALTH_BACKUP_TIMESTAMP" 2>/dev/null); then
        printf "%-22s: %s\n" "Age" "$(health_age_human "$backup_age_hours")"
        if health_age_warns "$backup_age_hours" "$HEALTH_BACKUP_HOURS"; then
            warnings=$((warnings + 1)); warning_messages+=("Latest backup is older than the warning threshold.")
        fi
    else
        printf "%-22s: not available\n" "Age"
        warnings=$((warnings + 1)); warning_messages+=("No backup history is available.")
    fi
    printf "%-22s: %s\n" "Rsync Exit Code" "$HEALTH_BACKUP_EXIT_CODE"
    printf "%-22s: %s\n" "Rsync Classification" "$HEALTH_BACKUP_RSYNC_CLASS"

    health_print_heading "Remote Backup Contents"
    printf "%-22s: %s\n" "Backup Size" "${HEALTH_REMOTE_BACKUP_SIZE:-not available}"
    printf "%-22s: %s\n" "Top-level Entries" "${HEALTH_REMOTE_TOP_LEVEL:-not available}"
    printf "%-22s: %s\n" "Recovery Guide" "${HEALTH_REMOTE_GUIDE:-not available}"
    printf "%-22s: %s\n" "Inventory" "${HEALTH_REMOTE_INVENTORY:-not available}"
    printf "%-22s: %s\n" "Integrity Directory" "${HEALTH_REMOTE_INTEGRITY_DIRECTORY:-not available}"
    if [ "${HEALTH_REMOTE_GUIDE:-no}" != "yes" ]; then warnings=$((warnings + 1)); warning_messages+=("Recovery guide metadata is missing."); fi
    if [ "${HEALTH_REMOTE_INVENTORY:-no}" != "yes" ]; then warnings=$((warnings + 1)); warning_messages+=("Inventory metadata is missing."); fi

    health_local_integrity_state "$MANIFEST_DIR/integrity/remote" || failures=$((failures + 1))
    health_print_heading "Integrity"
    printf "%-22s: %s\n" "Remote Newest" "${HEALTH_REMOTE_INTEGRITY_NEWEST:-none}"
    printf "%-22s: %s\n" "Remote latest.txt" "${HEALTH_REMOTE_LATEST_STATUS:-not available}"
    printf "%-22s: %s\n" "Latest Matches Newest" "${HEALTH_REMOTE_LATEST_MATCHES:-not available}"
    printf "%-22s: %s\n" "Local Reference" "${HEALTH_LOCAL_REFERENCE:-none}"
    printf "%-22s: %s\n" "Local Latest Matches" "${HEALTH_LOCAL_LATEST_MATCHES:-not applicable}"
    if [ "${HEALTH_LOCAL_REFERENCE:-none}" = "${HEALTH_REMOTE_INTEGRITY_NEWEST:-none}" ]; then
        printf "%-22s: yes\n" "Local/Remote Agreement"
    else
        printf "%-22s: no\n" "Local/Remote Agreement"
        warnings=$((warnings + 1)); warning_messages+=("Local and remote integrity references do not agree.")
    fi
    if integrity_timestamp=$(health_integrity_filename_timestamp "${HEALTH_REMOTE_INTEGRITY_NEWEST:-}"); then
        if integrity_age_hours=$(health_age_hours "$integrity_timestamp"); then
            printf "%-22s: %s\n" "Age" "$(health_age_human "$integrity_age_hours")"
            if health_age_warns "$integrity_age_hours" "$HEALTH_INTEGRITY_HOURS"; then
                warnings=$((warnings + 1)); warning_messages+=("Newest integrity reference is older than the warning threshold.")
            fi
        fi
    elif [ "${HEALTH_REMOTE_INTEGRITY_NEWEST:-none}" != "none" ]; then
        failures=$((failures + 1))
    fi
    if [ "${HEALTH_REMOTE_LATEST_MATCHES:-not applicable}" = "no" ] ||
        [ "${HEALTH_LOCAL_LATEST_MATCHES:-not applicable}" = "no" ]; then
        warnings=$((warnings + 1)); warning_messages+=("A latest.txt reference does not match the newest manifest.")
    fi

    health_print_heading "Retention"
    printf "%-22s: %s\n" "Retention Count" "$RETENTION_COUNT"
    printf "%-22s: %s\n" "Timestamped Files" "${HEALTH_REMOTE_INTEGRITY_COUNT:-0}"
    printf "%-22s: %s\n" "Retained" "${HEALTH_REMOTE_RETAINED:-0}"
    printf "%-22s: %s\n" "Eligible for Cleanup" "${HEALTH_REMOTE_ELIGIBLE:-0}"
    printf "%-22s: %s\n" "Suspicious Names" "${HEALTH_REMOTE_SUSPICIOUS:-0}"
    if [ "${HEALTH_REMOTE_ELIGIBLE:-0}" -ne 0 ]; then warnings=$((warnings + 1)); warning_messages+=("Integrity retention cleanup is eligible."); fi

    health_print_heading "Restore Readiness"
    printf "%-22s: %s\n" "Restore Assistant" "$(declare -F run_restore >/dev/null && printf PASS || printf FAIL)"
    printf "%-22s: %s\n" "Dry Run" "$(declare -F run_restore_dry_run >/dev/null && printf PASS || printf FAIL)"
    printf "%-22s: %s\n" "Confirmed Restore" "$(declare -F run_restore_confirm >/dev/null && printf PASS || printf FAIL)"
    printf "%-22s: %s\n" "Verification" "$(declare -F run_verify_restore >/dev/null && printf PASS || printf FAIL)"
    printf "%-22s: %s\n" "Recovery Guide" "$([ "${HEALTH_REMOTE_GUIDE:-no}" = yes ] && printf PASS || printf WARN)"
    printf "%-22s: %s\n" "Source Path Safety" "$(health_source_path_safe "$SOURCE" && printf PASS || printf FAIL)"
    printf "%-22s: %s\n" "Source Exists" "$([ -d "$SOURCE" ] && printf PASS || printf FAIL)"
    health_required_commands_available || failures=$((failures + 1))
    [ -d "$SOURCE" ] || failures=$((failures + 1))

    health_print_heading "Warnings"
    if [ "${#warning_messages[@]}" -eq 0 ]; then echo "- none"; else printf -- "- %s\n" "${warning_messages[@]}"; fi
    final_status=$(health_final_status "$failures" "$warnings")
    echo
    echo "HEALTH STATUS: $final_status"
    echo
    echo "Read-only health analysis."
    echo "No files were changed."
    case "$final_status" in PASS) return 0 ;; WARNING) return 1 ;; *) return 2 ;; esac
}
