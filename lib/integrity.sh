#!/bin/bash

integrity_path_supported() {
    [[ "$1" != *$'\n'* && "$1" != *$'\t'* ]]
}

integrity_generate_manifest() {
    local source_directory="$1"
    local output_file="$2"
    local creation_timestamp="$3"
    local entry file_hash file_size link_target relative_path
    local regular_files=0 symbolic_links=0 total_bytes=0
    local records_file="${output_file}.records"

    : > "$records_file"
    while IFS= read -r -d "" entry; do
        relative_path="${entry#"${source_directory%/}"/}"
        if ! integrity_path_supported "$relative_path"; then
            rm -f -- "$records_file"
            log_error "Integrity manifests do not support tabs or newlines in paths"
            return 1
        fi
        if [ -L "$entry" ]; then
            link_target=$(readlink -- "$entry") || return 1
            integrity_path_supported "$link_target" || return 1
            printf "L\t%s\t%s\n" "$relative_path" "$link_target" >> "$records_file"
            symbolic_links=$((symbolic_links + 1))
        else
            file_size=$(stat -c "%s" -- "$entry") || return 1
            file_hash=$(sha256sum -- "$entry") || return 1
            file_hash="${file_hash%% *}"
            printf "F\t%s\t%s\t%s\n" "$relative_path" "$file_size" "$file_hash" >> "$records_file"
            regular_files=$((regular_files + 1))
            total_bytes=$((total_bytes + file_size))
        fi
    done < <(find "${source_directory%/}" -mindepth 1 \( -type f -o -type l \) -print0 2>/dev/null | LC_ALL=C sort -z)

    {
        echo "# project-phoenix-integrity"
        echo "# format_version=1"
        printf "# created_at=%s\n" "$creation_timestamp"
        printf "# source=%s\n" "$(restore_normalize_directory "$source_directory")"
        printf "# regular_files=%s\n" "$regular_files"
        printf "# symbolic_links=%s\n" "$symbolic_links"
        printf "# total_bytes=%s\n" "$total_bytes"
        echo "# filename_limit=tabs and newlines are unsupported"
        echo "--"
        cat "$records_file"
    } > "$output_file"
    rm -f -- "$records_file"
}

integrity_load_manifest() {
    local manifest_file="$1"
    local -n file_sizes_ref="$2" file_hashes_ref="$3" links_ref="$4"
    local line path record_type value_one value_two
    local marker_seen=0 metadata_files="" metadata_links="" metadata_version=""

    file_sizes_ref=(); file_hashes_ref=(); links_ref=()
    [ -f "$manifest_file" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$marker_seen" -eq 0 ]; then
            case "$line" in
                "# format_version="*) metadata_version="${line#*=}" ;;
                "# regular_files="*) metadata_files="${line#*=}" ;;
                "# symbolic_links="*) metadata_links="${line#*=}" ;;
                --) marker_seen=1 ;;
            esac
            continue
        fi
        IFS=$'\t' read -r record_type path value_one value_two <<< "$line"
        [ -n "$path" ] || return 1
        case "$record_type" in
            F)
                [[ "$value_one" =~ ^[0-9]+$ && "$value_two" =~ ^[0-9a-f]{64}$ ]] || return 1
                [[ ! -v file_sizes_ref["$path"] && ! -v links_ref["$path"] ]] || return 1
                file_sizes_ref["$path"]="$value_one"
                # shellcheck disable=SC2034 # Nameref output consumed by integrity_compare_manifests.
                file_hashes_ref["$path"]="$value_two"
                ;;
            L)
                [ -n "$value_one" ] && [ -z "$value_two" ] || return 1
                [[ ! -v file_sizes_ref["$path"] && ! -v links_ref["$path"] ]] || return 1
                links_ref["$path"]="$value_one"
                ;;
            *) return 1 ;;
        esac
    done < "$manifest_file"
    [ "$metadata_version" = "1" ] && [[ "$metadata_files" =~ ^[0-9]+$ ]] &&
        [[ "$metadata_links" =~ ^[0-9]+$ ]] && [ "$marker_seen" -eq 1 ] &&
        [ "${#file_sizes_ref[@]}" -eq "$metadata_files" ] && [ "${#links_ref[@]}" -eq "$metadata_links" ]
}

integrity_compare_manifests() {
    local expected_manifest="$1" actual_manifest="$2" path
    local -A actual_file_hashes=() actual_file_sizes=() actual_links=()
    local -A expected_file_hashes=() expected_file_sizes=() expected_links=()
    integrity_load_manifest "$expected_manifest" expected_file_sizes expected_file_hashes expected_links || return 2
    integrity_load_manifest "$actual_manifest" actual_file_sizes actual_file_hashes actual_links || return 2

    INTEGRITY_EXPECTED_FILES=${#expected_file_sizes[@]}; INTEGRITY_ACTUAL_FILES=${#actual_file_sizes[@]}
    INTEGRITY_EXPECTED_LINKS=${#expected_links[@]}; INTEGRITY_ACTUAL_LINKS=${#actual_links[@]}
    INTEGRITY_MISSING_FILES=(); INTEGRITY_UNEXPECTED_FILES=(); INTEGRITY_CHANGED_SIZES=(); INTEGRITY_CHANGED_HASHES=()
    INTEGRITY_MISSING_LINKS=(); INTEGRITY_UNEXPECTED_LINKS=(); INTEGRITY_CHANGED_LINK_TARGETS=()
    for path in "${!expected_file_sizes[@]}"; do
        if [[ ! -v actual_file_sizes["$path"] ]]; then INTEGRITY_MISSING_FILES+=("$path"); else
            [ "${expected_file_sizes[$path]}" = "${actual_file_sizes[$path]}" ] || INTEGRITY_CHANGED_SIZES+=("$path")
            [ "${expected_file_hashes[$path]}" = "${actual_file_hashes[$path]}" ] || INTEGRITY_CHANGED_HASHES+=("$path")
        fi
    done
    for path in "${!actual_file_sizes[@]}"; do [[ -v expected_file_sizes["$path"] ]] || INTEGRITY_UNEXPECTED_FILES+=("$path"); done
    for path in "${!expected_links[@]}"; do
        if [[ ! -v actual_links["$path"] ]]; then INTEGRITY_MISSING_LINKS+=("$path")
        elif [ "${expected_links[$path]}" != "${actual_links[$path]}" ]; then INTEGRITY_CHANGED_LINK_TARGETS+=("$path"); fi
    done
    for path in "${!actual_links[@]}"; do [[ -v expected_links["$path"] ]] || INTEGRITY_UNEXPECTED_LINKS+=("$path"); done
}

integrity_print_examples() {
    local heading="$1"; shift
    [ "$#" -ne 0 ] || return 0
    printf "\n%s\n" "$heading"; echo "-------------------------"
    printf "%s\n" "$@" | LC_ALL=C sort | head -n 25
}

integrity_validate_source() {
    [ -d "$SOURCE" ] && restore_target_is_safe "$SOURCE" "$PROJECT_ROOT" && restore_local_target_accessible "$SOURCE"
}

run_integrity_create() {
    local integrity_directory manifest_file timestamp
    validate_config || return 1
    section "PROJECT PHOENIX INTEGRITY MANIFEST"
    discovery_has_command sha256sum || { log_error "sha256sum is not installed"; return 1; }
    integrity_validate_source || { log_error "SOURCE is missing, inaccessible, or unsafe"; return 1; }
    integrity_directory="$MANIFEST_DIR/integrity"; timestamp=$(date +%Y%m%d-%H%M%S)
    manifest_file="$integrity_directory/integrity-$timestamp.txt"
    mkdir -p "$integrity_directory"
    [ ! -e "$manifest_file" ] || { log_error "Timestamped integrity manifest already exists"; return 1; }
    INTEGRITY_TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/project-phoenix-integrity.XXXXXX") || return 1
    trap 'rm -rf -- "$INTEGRITY_TEMP_DIR"' EXIT HUP INT TERM
    integrity_generate_manifest "$SOURCE" "$INTEGRITY_TEMP_DIR/manifest.txt" "$(date -Iseconds)" || return 1
    cp -- "$INTEGRITY_TEMP_DIR/manifest.txt" "$manifest_file"
    cp -- "$INTEGRITY_TEMP_DIR/manifest.txt" "$integrity_directory/latest.txt"
    rm -rf -- "$INTEGRITY_TEMP_DIR"; trap - EXIT HUP INT TERM
    log_success "Integrity manifest created"; echo "Manifest: $manifest_file"; echo "Latest  : $integrity_directory/latest.txt"
}

run_integrity_verify() {
    local actual_manifest compare_exit_code mismatch_total
    local manifest_file="${1:-$MANIFEST_DIR/integrity/latest.txt}"
    validate_config || return 1
    section "PROJECT PHOENIX INTEGRITY VERIFICATION"
    discovery_has_command sha256sum || { log_error "sha256sum is not installed"; return 1; }
    integrity_validate_source || { log_error "SOURCE is missing, inaccessible, or unsafe"; return 1; }
    [ -f "$manifest_file" ] || { log_error "Integrity manifest is missing: $manifest_file"; return 1; }
    INTEGRITY_TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/project-phoenix-integrity.XXXXXX") || return 1
    trap 'rm -rf -- "$INTEGRITY_TEMP_DIR"' EXIT HUP INT TERM
    actual_manifest="$INTEGRITY_TEMP_DIR/actual.txt"
    integrity_generate_manifest "$SOURCE" "$actual_manifest" "verification" || return 1
    if integrity_compare_manifests "$manifest_file" "$actual_manifest"; then compare_exit_code=0; else compare_exit_code=$?; fi
    [ "$compare_exit_code" -ne 2 ] || { log_error "Integrity manifest is malformed"; return 1; }

    printf "%-21s: %s\n" "Source" "$(restore_normalize_directory "$SOURCE")"
    printf "%-21s: %s\n" "Manifest" "$manifest_file"
    printf "%-21s: %s\n" "Expected Files" "$INTEGRITY_EXPECTED_FILES"; printf "%-21s: %s\n" "Actual Files" "$INTEGRITY_ACTUAL_FILES"
    printf "%-21s: %s\n" "Expected Symlinks" "$INTEGRITY_EXPECTED_LINKS"; printf "%-21s: %s\n" "Actual Symlinks" "$INTEGRITY_ACTUAL_LINKS"
    printf "%-21s: %s\n" "Missing Files" "${#INTEGRITY_MISSING_FILES[@]}"; printf "%-21s: %s\n" "Unexpected Files" "${#INTEGRITY_UNEXPECTED_FILES[@]}"
    printf "%-21s: %s\n" "Changed Sizes" "${#INTEGRITY_CHANGED_SIZES[@]}"; printf "%-21s: %s\n" "Changed Hashes" "${#INTEGRITY_CHANGED_HASHES[@]}"
    printf "%-21s: %s\n" "Missing Symlinks" "${#INTEGRITY_MISSING_LINKS[@]}"; printf "%-21s: %s\n" "Unexpected Symlinks" "${#INTEGRITY_UNEXPECTED_LINKS[@]}"
    printf "%-21s: %s\n" "Changed Link Targets" "${#INTEGRITY_CHANGED_LINK_TARGETS[@]}"
    integrity_print_examples "Missing Files" "${INTEGRITY_MISSING_FILES[@]}"; integrity_print_examples "Unexpected Files" "${INTEGRITY_UNEXPECTED_FILES[@]}"
    integrity_print_examples "Changed Sizes" "${INTEGRITY_CHANGED_SIZES[@]}"; integrity_print_examples "Changed Hashes" "${INTEGRITY_CHANGED_HASHES[@]}"
    integrity_print_examples "Missing Symlinks" "${INTEGRITY_MISSING_LINKS[@]}"; integrity_print_examples "Unexpected Symlinks" "${INTEGRITY_UNEXPECTED_LINKS[@]}"
    integrity_print_examples "Changed Link Targets" "${INTEGRITY_CHANGED_LINK_TARGETS[@]}"
    mismatch_total=$((${#INTEGRITY_MISSING_FILES[@]} + ${#INTEGRITY_UNEXPECTED_FILES[@]} + ${#INTEGRITY_CHANGED_SIZES[@]} + ${#INTEGRITY_CHANGED_HASHES[@]} + ${#INTEGRITY_MISSING_LINKS[@]} + ${#INTEGRITY_UNEXPECTED_LINKS[@]} + ${#INTEGRITY_CHANGED_LINK_TARGETS[@]}))
    rm -rf -- "$INTEGRITY_TEMP_DIR"; trap - EXIT HUP INT TERM
    echo
    if [ "$mismatch_total" -eq 0 ]; then echo "INTEGRITY STATUS: PASS"; echo; echo "No files were changed."; echo "Docker containers were not started."; return 0; fi
    echo "INTEGRITY STATUS: FAILED"; echo; echo "No files were changed."; echo "Docker containers were not started."; return 1
}
