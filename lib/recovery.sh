#!/bin/bash

recovery_count_top_level_entries() {
    find "$1" -mindepth 1 -maxdepth 1 -print 2>/dev/null | wc -l
}

recovery_count_compose_files() {
    find "$1" -type f \
        \( -name compose.yml -o -name compose.yaml -o \
           -name docker-compose.yml -o -name docker-compose.yaml \) \
        -print 2>/dev/null | wc -l
}

recovery_list_compose_projects() {
    local directory="$1"
    local compose_file
    local relative_path
    local root_directory="${directory%/}"

    [ -n "$root_directory" ] || root_directory="/"

    find "$root_directory" -type f \
        \( -name compose.yml -o -name compose.yaml -o \
           -name docker-compose.yml -o -name docker-compose.yaml \) \
        -print 2>/dev/null |
        while IFS= read -r compose_file; do
            relative_path="${compose_file#"$root_directory"/}"
            case "$relative_path" in
                */*) printf "%s\n" "${relative_path%%/*}" ;;
                *) printf ".\n" ;;
            esac
        done |
        LC_ALL=C sort -u |
        head -n 25
}

recovery_has_inventory() {
    find "$1" \
        \( -type d -iname inventory -o -type f -iname "*inventory*" \) \
        -print -quit 2>/dev/null | grep -q .
}

recovery_has_manifest() {
    find "$1" \
        \( -type d -iname manifests -o -type f -iname "*manifest*" \) \
        -print -quit 2>/dev/null | grep -q .
}

recovery_has_restore_guide() {
    find "$1" -type f \
        \( -iname "restore*.md" -o -iname "restore*.txt" -o \
           -iname "recovery*.md" -o -iname "recovery*.txt" -o \
           -ipath "*/restore/README.md" -o \
           -ipath "*/restore/README.txt" -o \
           -ipath "*/recovery/README.md" -o \
           -ipath "*/recovery/README.txt" -o \
           -ipath "*/disaster-recovery/README.md" -o \
           -ipath "*/disaster-recovery/README.txt" \) \
        -print -quit 2>/dev/null | grep -q .
}

recovery_analyse_local_directory() {
    local directory="$1"
    local inventory="not found"
    local manifest="not found"
    local restore_guide="not found"

    recovery_has_inventory "$directory" && inventory="found"
    recovery_has_manifest "$directory" && manifest="found"
    recovery_has_restore_guide "$directory" && restore_guide="found"

    printf "backup_size=%s\n" "$(du -sh -- "$directory" 2>/dev/null | awk "{print \$1}")"
    printf "top_level_entries=%s\n" "$(recovery_count_top_level_entries "$directory")"
    printf "compose_files=%s\n" "$(recovery_count_compose_files "$directory")"
    while IFS= read -r compose_project; do
        [ -n "$compose_project" ] && printf "compose_project=%s\n" "$compose_project"
    done < <(recovery_list_compose_projects "$directory")
    printf "inventory=%s\n" "$inventory"
    printf "manifest=%s\n" "$manifest"
    printf "restore_guide=%s\n" "$restore_guide"
    printf "integrity_manifest=%s\n" "not found"
    printf "integrity_reference=%s\n" "not available"
}

recovery_parse_analysis() {
    local analysis="$1"
    local key
    local value

    RECOVERY_BACKUP_SIZE=""
    RECOVERY_TOP_LEVEL_ENTRIES=""
    RECOVERY_COMPOSE_FILES=""
    RECOVERY_COMPOSE_PROJECTS=()
    RECOVERY_INVENTORY=""
    RECOVERY_MANIFEST=""
    RECOVERY_RESTORE_GUIDE=""
    RECOVERY_INTEGRITY_MANIFEST=""
    RECOVERY_INTEGRITY_REFERENCE=""

    while IFS="=" read -r key value; do
        case "$key" in
            backup_size) RECOVERY_BACKUP_SIZE="$value" ;;
            top_level_entries) RECOVERY_TOP_LEVEL_ENTRIES="$value" ;;
            compose_files) RECOVERY_COMPOSE_FILES="$value" ;;
            compose_project) RECOVERY_COMPOSE_PROJECTS+=("$value") ;;
            inventory) RECOVERY_INVENTORY="$value" ;;
            manifest) RECOVERY_MANIFEST="$value" ;;
            restore_guide) RECOVERY_RESTORE_GUIDE="$value" ;;
            integrity_manifest) RECOVERY_INTEGRITY_MANIFEST="$value" ;;
            integrity_reference) RECOVERY_INTEGRITY_REFERENCE="$value" ;;
        esac
    done <<< "$analysis"

    [ -n "$RECOVERY_BACKUP_SIZE" ] &&
        [[ "$RECOVERY_TOP_LEVEL_ENTRIES" =~ ^[0-9]+$ ]] &&
        [[ "$RECOVERY_COMPOSE_FILES" =~ ^[0-9]+$ ]] &&
        [[ "$RECOVERY_INVENTORY" =~ ^(found|not\ found)$ ]] &&
        [[ "$RECOVERY_MANIFEST" =~ ^(found|not\ found)$ ]] &&
        [[ "$RECOVERY_RESTORE_GUIDE" =~ ^(found|not\ found)$ ]] &&
        [[ "$RECOVERY_INTEGRITY_MANIFEST" =~ ^(found|not\ found)$ ]]
}

recovery_remote_analysis() {
    ssh_run_read_only_destination_script \
        "$SSH_KEY" "$BACKUP_USER" "$BACKUP_HOST" "$DESTINATION" \
        accept-new <<\REMOTE_ANALYSIS
set -u

[ -d "$destination" ] || exit 1
[ -r "$destination" ] || exit 1

inventory="not found"
manifest="not found"
restore_guide="not found"
integrity_manifest="not found"
integrity_reference="not available"

if find "$destination" \( -type d -iname inventory -o -type f -iname "*inventory*" \) -print -quit 2>/dev/null | grep -q .; then
    inventory="found"
fi
if find "$destination" \( -type d -iname manifests -o -type f -iname "*manifest*" \) -print -quit 2>/dev/null | grep -q .; then
    manifest="found"
fi
if find "$destination" -type f \( -iname "restore*.md" -o -iname "restore*.txt" -o -iname "recovery*.md" -o -iname "recovery*.txt" -o -ipath "*/restore/README.md" -o -ipath "*/restore/README.txt" -o -ipath "*/recovery/README.md" -o -ipath "*/recovery/README.txt" -o -ipath "*/disaster-recovery/README.md" -o -ipath "*/disaster-recovery/README.txt" \) -print -quit 2>/dev/null | grep -q .; then
    restore_guide="found"
fi
integrity_directory="${destination%/}/backup/manifests/integrity"
if [ -f "$integrity_directory/latest.txt" ]; then
    integrity_manifest="found"
    integrity_reference=$(find "$integrity_directory" -maxdepth 1 -type f -name "integrity-*.txt" -printf "%f\n" 2>/dev/null | LC_ALL=C sort | tail -n 1)
    [ -n "$integrity_reference" ] || integrity_reference="latest.txt"
fi

backup_size=$(du -sh -- "$destination" 2>/dev/null | awk "{print \$1}") || exit 1
top_level_entries=$(find "$destination" -mindepth 1 -maxdepth 1 -print 2>/dev/null | wc -l) || exit 1
compose_files=$(find "$destination" -type f \( -name compose.yml -o -name compose.yaml -o -name docker-compose.yml -o -name docker-compose.yaml \) -print 2>/dev/null | wc -l) || exit 1
analysis_root=${destination%/}
[ -n "$analysis_root" ] || analysis_root="/"
compose_projects=$(
    find "$analysis_root" -type f \( -name compose.yml -o -name compose.yaml -o -name docker-compose.yml -o -name docker-compose.yaml \) -print 2>/dev/null |
        while IFS= read -r compose_file; do
            relative_path=${compose_file#"$analysis_root"/}
            case "$relative_path" in
                */*) printf "%s\n" "${relative_path%%/*}" ;;
                *) printf ".\n" ;;
            esac
        done |
        LC_ALL=C sort -u |
        head -n 25
) || exit 1

[ -n "$backup_size" ] || exit 1
printf "backup_size=%s\n" "$backup_size"
printf "top_level_entries=%s\n" "$top_level_entries"
printf "compose_files=%s\n" "$compose_files"
if [ -n "$compose_projects" ]; then
    printf "%s\n" "$compose_projects" | while IFS= read -r compose_project; do
        printf "compose_project=%s\n" "$compose_project"
    done
fi
printf "inventory=%s\n" "$inventory"
printf "manifest=%s\n" "$manifest"
printf "restore_guide=%s\n" "$restore_guide"
printf "integrity_manifest=%s\n" "$integrity_manifest"
printf "integrity_reference=%s\n" "$integrity_reference"
REMOTE_ANALYSIS
}

run_recovery() {
    local analysis

    if ! validate_config; then
        log_error "Recovery analysis stopped because configuration is invalid"
        return 1
    fi

    section "PROJECT PHOENIX RECOVERY ANALYSIS"

    if ! discovery_has_command ssh; then
        log_error "SSH client is not installed"
        return 1
    fi

    if ! ssh_key_exists "$SSH_KEY"; then
        log_error "Configured SSH key file does not exist"
        return 1
    fi

    if ! ssh_test_connection "$SSH_KEY" "$BACKUP_USER" "$BACKUP_HOST" accept-new; then
        log_error "SSH connection failed"
        return 1
    fi
    log_success "SSH connection successful"

    if ! ssh_remote_destination_exists \
        "$SSH_KEY" "$BACKUP_USER" "$BACKUP_HOST" "$DESTINATION" \
        accept-new; then
        log_error "Backup destination was not found"
        return 1
    fi
    log_success "Backup destination found"

    if ! analysis=$(recovery_remote_analysis 2>/dev/null); then
        log_error "Backup destination could not be read"
        return 1
    fi

    if ! recovery_parse_analysis "$analysis"; then
        log_error "Backup analysis returned invalid results"
        return 1
    fi
    log_success "Backup is readable"

    echo
    printf "%-18s: %s\n" "Backup Size" "$RECOVERY_BACKUP_SIZE"
    printf "%-18s: %s\n" "Top-level Entries" "$RECOVERY_TOP_LEVEL_ENTRIES"
    printf "%-18s: %s\n" "Compose Files" "$RECOVERY_COMPOSE_FILES"
    printf "%-18s: %s\n" "Inventory" "$RECOVERY_INVENTORY"
    printf "%-18s: %s\n" "Manifest" "$RECOVERY_MANIFEST"
    printf "%-18s: %s\n" "Restore Guide" "$RECOVERY_RESTORE_GUIDE"
    printf "%-18s: %s\n" "Integrity Manifest" "$RECOVERY_INTEGRITY_MANIFEST"
    printf "%-18s: %s\n" "Integrity Reference" "$RECOVERY_INTEGRITY_REFERENCE"
    echo
    echo "Compose Projects"
    echo "----------------"
    if [ "${#RECOVERY_COMPOSE_PROJECTS[@]}" -eq 0 ]; then
        echo "(none found)"
    else
        printf "%s\n" "${RECOVERY_COMPOSE_PROJECTS[@]}"
    fi
    echo
    echo "RECOVERY STATUS: READY"
    echo
    echo "No files have been restored."
    echo "Run the future restore-confirm command to begin recovery."
}
