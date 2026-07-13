#!/bin/bash

verification_count_records() {
    awk "NF { count++ } END { print count + 0 }"
}
verification_resolve_expected_services_mode() {
    local configured_mode="${1:-auto}"
    local target_directory="$2"
    local normalized_target="${target_directory%/}"

    VERIFY_EXPECTED_MODE_FALLBACK="no"
    case "$configured_mode" in
        auto|required|advisory|disabled) VERIFY_EXPECTED_SERVICES_MODE="$configured_mode" ;;
        *) VERIFY_EXPECTED_SERVICES_MODE="auto"; VERIFY_EXPECTED_MODE_FALLBACK="yes" ;;
    esac
    VERIFY_EXPECTED_EFFECTIVE_MODE="$VERIFY_EXPECTED_SERVICES_MODE"
    if [ "$VERIFY_EXPECTED_SERVICES_MODE" = "auto" ]; then
        case "$normalized_target" in
            /volume2/docker|/volume2/docker/*) VERIFY_EXPECTED_EFFECTIVE_MODE="required" ;;
            *)
                if [ -f "$target_directory/backup/manifests/expected-services.txt" ] ||
                    [ -f "$target_directory/.project-phoenix-recovery-required" ] ||
                    find "$target_directory/backup/manifests/inventory" -mindepth 2 -maxdepth 2 -type f -name expected-services.txt -print -quit 2>/dev/null | grep -q .; then
                    VERIFY_EXPECTED_EFFECTIVE_MODE="required"
                else
                    VERIFY_EXPECTED_EFFECTIVE_MODE="advisory"
                fi
                ;;
        esac
    fi
}

verification_compare_expected_services() {
    local source_directory="$1"
    local expected_services_value="$2"
    local service
    local -a expected_services=()

    VERIFY_EXPECTED_FOUND=0
    VERIFY_EXPECTED_MISSING=0
    VERIFY_EXPECTED_SKIPPED="no"
    VERIFY_MISSING_SERVICES=()

    if [ "${VERIFY_EXPECTED_EFFECTIVE_MODE:-advisory}" = "disabled" ] ||
        [ -z "$expected_services_value" ]; then
        VERIFY_EXPECTED_SKIPPED="yes"
        return 0
    fi

    read -r -a expected_services <<< "$expected_services_value"
    for service in "${expected_services[@]}"; do
        if [[ "$service" == */* ]] || [ ! -d "$source_directory/$service" ]; then
            VERIFY_MISSING_SERVICES+=("$service")
            VERIFY_EXPECTED_MISSING=$((VERIFY_EXPECTED_MISSING + 1))
        else
            VERIFY_EXPECTED_FOUND=$((VERIFY_EXPECTED_FOUND + 1))
        fi
    done
}

verification_analyse_source() {
    local source_directory="$1"

    VERIFY_TOTAL_SIZE=$(du -sh -- "$source_directory" 2>/dev/null | awk "{print \$1}")
    VERIFY_FILES=$(find "$source_directory" -mindepth 1 -type f -print 2>/dev/null | verification_count_records)
    VERIFY_DIRECTORIES=$(find "$source_directory" -mindepth 1 -type d -print 2>/dev/null | verification_count_records)
    VERIFY_SYMLINKS=$(find "$source_directory" -mindepth 1 -type l -print 2>/dev/null | verification_count_records)
    VERIFY_TOP_LEVEL_ENTRIES=$(recovery_count_top_level_entries "$source_directory")
    VERIFY_COMPOSE_FILES=$(recovery_count_compose_files "$source_directory")
    mapfile -t VERIFY_COMPOSE_PROJECTS < <(recovery_list_compose_projects "$source_directory")
    VERIFY_UNREADABLE_FILES=$(find "$source_directory" -mindepth 1 -type f ! -readable -print 2>/dev/null | verification_count_records)
    VERIFY_UNREADABLE_DIRECTORIES=$(find "$source_directory" -mindepth 1 -type d \( ! -readable -o ! -executable \) -print 2>/dev/null | verification_count_records)
    VERIFY_BROKEN_SYMLINKS=$(find "$source_directory" -mindepth 1 -xtype l -print 2>/dev/null | verification_count_records)
    VERIFY_EMPTY_TOP_LEVEL_DIRECTORIES=$(find "$source_directory" -mindepth 1 -maxdepth 1 -type d -empty -print 2>/dev/null | verification_count_records)

    VERIFY_INVENTORY="not found"
    VERIFY_MANIFEST="not found"
    VERIFY_RESTORE_GUIDE="not found"
    recovery_has_inventory "$source_directory" && VERIFY_INVENTORY="found"
    recovery_has_manifest "$source_directory" && VERIFY_MANIFEST="found"
    recovery_has_restore_guide "$source_directory" && VERIFY_RESTORE_GUIDE="found"

    [ -n "$VERIFY_TOTAL_SIZE" ]
}

verification_evaluate_status() {
    if [ "$VERIFY_FILES" -eq 0 ] ||
        [ "$VERIFY_UNREADABLE_FILES" -ne 0 ] ||
        [ "$VERIFY_UNREADABLE_DIRECTORIES" -ne 0 ] ||
        [ "$VERIFY_BROKEN_SYMLINKS" -ne 0 ] ||
        { [ "$VERIFY_EXPECTED_MISSING" -ne 0 ] &&
            [ "${VERIFY_EXPECTED_EFFECTIVE_MODE:-required}" = "required" ]; }; then
        printf "%s\n" "FAILED"
        return 1
    fi

    if { [ "$VERIFY_EXPECTED_SKIPPED" = "yes" ] &&
            [ "${VERIFY_EXPECTED_EFFECTIVE_MODE:-advisory}" != "disabled" ]; } ||
        [ "$VERIFY_COMPOSE_FILES" -eq 0 ] ||
        [ "$VERIFY_INVENTORY" != "found" ] ||
        [ "$VERIFY_MANIFEST" != "found" ] ||
        [ "$VERIFY_RESTORE_GUIDE" != "found" ] ||
        { [ "$VERIFY_EXPECTED_MISSING" -ne 0 ] &&
            [ "${VERIFY_EXPECTED_EFFECTIVE_MODE:-required}" = "advisory" ]; } ||
        [ "$VERIFY_EMPTY_TOP_LEVEL_DIRECTORIES" -ne 0 ]; then
        printf "%s\n" "WARNING"
        return 0
    fi

    printf "%s\n" "PASS"
}

verification_expected_services_status() {
    if [ "$VERIFY_EXPECTED_SKIPPED" = "yes" ]; then
        if [ "$VERIFY_EXPECTED_EFFECTIVE_MODE" = "disabled" ]; then printf "SKIPPED\n"; else printf "NOT CONFIGURED\n"; fi
    elif [ "$VERIFY_EXPECTED_MISSING" -eq 0 ]; then
        printf "PASS\n"
    elif [ "$VERIFY_EXPECTED_EFFECTIVE_MODE" = "required" ]; then
        printf "FAILED\n"
    else
        printf "WARNING\n"
    fi
}

run_verify_restore() {
    local verify_status

    if ! validate_config; then
        log_error "Restore verification stopped because configuration is invalid"
        return 1
    fi

    section "PROJECT PHOENIX RESTORE VERIFICATION"

    if [ ! -d "$SOURCE" ]; then
        log_error "Restore target is missing or is not a directory"
        echo
        echo "VERIFY STATUS: FAILED"
        return 1
    fi
    if ! restore_target_is_safe "$SOURCE" "$PROJECT_ROOT"; then
        log_error "Restore target is protected or unsafe"
        echo
        echo "VERIFY STATUS: FAILED"
        return 1
    fi
    if ! restore_local_target_accessible "$SOURCE"; then
        log_error "Restore target is not readable and searchable"
        echo
        echo "VERIFY STATUS: FAILED"
        return 1
    fi

    if ! verification_analyse_source "$SOURCE"; then
        log_error "Restore target analysis failed"
        echo
        echo "VERIFY STATUS: FAILED"
        return 1
    fi
    verification_resolve_expected_services_mode "${VERIFY_EXPECTED_SERVICES_MODE:-auto}" "$SOURCE"
    [ "$VERIFY_EXPECTED_MODE_FALLBACK" = "no" ] || log_warning "Invalid expected-services mode; defaulting to auto"
    verification_compare_expected_services "$SOURCE" "${EXPECTED_SERVICES:-}"
    printf "%-25s: %s\n" "Structural Verification" "$(VERIFY_EXPECTED_MISSING=0 verification_evaluate_status)"
    printf "%-25s: %s (%s)\n" "Expected Services Mode" "$VERIFY_EXPECTED_SERVICES_MODE" "$VERIFY_EXPECTED_EFFECTIVE_MODE"
    printf "%-25s: %s\n" "Expected Services Result" "$(verification_expected_services_status)"

    printf "%-23s: %s\n" "Restore Target" "$(restore_normalize_directory "$SOURCE")"
    printf "%-23s: %s\n" "Total Size" "$VERIFY_TOTAL_SIZE"
    printf "%-23s: %s\n" "Files" "$VERIFY_FILES"
    printf "%-23s: %s\n" "Directories" "$VERIFY_DIRECTORIES"
    printf "%-23s: %s\n" "Symbolic Links" "$VERIFY_SYMLINKS"
    printf "%-23s: %s\n" "Top-level Entries" "$VERIFY_TOP_LEVEL_ENTRIES"
    printf "%-23s: %s\n" "Compose Files" "$VERIFY_COMPOSE_FILES"
    if [ "$VERIFY_EXPECTED_SKIPPED" = "yes" ]; then
        printf "%-23s: %s\n" "Expected Services" "comparison skipped"
    else
        printf "%-23s: %s found, %s missing\n" \
            "Expected Services" "$VERIFY_EXPECTED_FOUND" "$VERIFY_EXPECTED_MISSING"
    fi
    printf "%-23s: %s\n" "Unreadable Files" "$VERIFY_UNREADABLE_FILES"
    printf "%-23s: %s\n" "Unreadable Directories" "$VERIFY_UNREADABLE_DIRECTORIES"
    printf "%-23s: %s\n" "Broken Symlinks" "$VERIFY_BROKEN_SYMLINKS"
    printf "%-23s: %s\n" "Empty Top-level Dirs" "$VERIFY_EMPTY_TOP_LEVEL_DIRECTORIES"
    printf "%-23s: %s\n" "Inventory" "$VERIFY_INVENTORY"
    printf "%-23s: %s\n" "Manifest" "$VERIFY_MANIFEST"
    printf "%-23s: %s\n" "Restore Guide" "$VERIFY_RESTORE_GUIDE"

    echo
    echo "Compose Projects"
    echo "----------------"
    if [ "${#VERIFY_COMPOSE_PROJECTS[@]}" -eq 0 ]; then
        echo "(none found)"
    else
        printf "%s\n" "${VERIFY_COMPOSE_PROJECTS[@]}"
    fi

    if [ "$VERIFY_EXPECTED_MISSING" -ne 0 ] &&
        [ "$VERIFY_EXPECTED_EFFECTIVE_MODE" != "disabled" ]; then
        echo
        echo "Missing Expected Services"
        echo "-------------------------"
        printf "%s\n" "${VERIFY_MISSING_SERVICES[@]}"
    fi

    if verify_status=$(verification_evaluate_status); then
        :
    else
        echo
        echo "VERIFY STATUS: $verify_status"
        echo
        echo "No files were changed."
        echo "Docker containers were not started."
        return 1
    fi

    echo
    echo "VERIFY STATUS: $verify_status"
    echo
    echo "No files were changed."
    echo "Docker containers were not started."
}
