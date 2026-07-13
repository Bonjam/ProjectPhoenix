#!/bin/bash

backup_inventory_compose_files() {
    find "$1" -type f \( -name docker-compose.yml -o -name docker-compose.yaml -o -name compose.yml -o -name compose.yaml \) -print
}

backup_inventory_source_sizes() {
    local entry
    while IFS= read -r -d "" entry; do du -sh -- "$entry" || return 1; done < <(find "$1" -mindepth 1 -maxdepth 1 -print0)
}

backup_inventory_runtime_placeholder() {
    printf "%s\n" "$2" > "$1"
}

backup_inventory_capture_docker() {
    local output_file="$1" docker_command="$2"
    shift 2
    if "$docker_command" "$@" > "$output_file" 2>&1; then return 0; fi
    printf "Docker command failed: %s\n" "$*" >> "$output_file"
    return 1
}
backup_write_service_policy_metadata() {
    local production_recovery="no"

    BACKUP_INVENTORY_ORIGINAL_SOURCE=$(service_policy_normalize_path "$SOURCE") || return 1
    case "$BACKUP_INVENTORY_ORIGINAL_SOURCE" in
        *$'\n'*|*$'\r'*) return 1 ;;
    esac
    BACKUP_EXPECTED_SERVICES_POLICY=$(service_policy_resolve_for_source \
        "${VERIFY_EXPECTED_SERVICES_MODE:-auto}" "$BACKUP_INVENTORY_ORIGINAL_SOURCE") || return 1
    if service_policy_path_is_production_docker "$BACKUP_INVENTORY_ORIGINAL_SOURCE"; then
        production_recovery="yes"
    fi
    BACKUP_PRODUCTION_DOCKER_RECOVERY="$production_recovery"
    {
        printf "original_source=%s\n" "$BACKUP_INVENTORY_ORIGINAL_SOURCE"
        printf "expected_services_policy=%s\n" "$BACKUP_EXPECTED_SERVICES_POLICY"
        printf "production_docker_recovery=%s\n" "$BACKUP_PRODUCTION_DOCKER_RECOVERY"
    } > "$INVENTORY_DIR/service-policy.txt"
}


backup_generate_filesystem_inventory() {
    local compose_collector="${1:-backup_inventory_compose_files}"
    local size_collector="${2:-backup_inventory_source_sizes}"

    BACKUP_FILESYSTEM_INVENTORY_STATUS="failed"
    BACKUP_FILESYSTEM_INVENTORY_FAILURE=""
    mkdir -p "$INVENTORY_DIR" || { BACKUP_FILESYSTEM_INVENTORY_FAILURE="inventory directory creation"; return 1; }
    if ! backup_write_service_policy_metadata; then
        BACKUP_FILESYSTEM_INVENTORY_FAILURE="service-policy metadata"
        return 1
    fi
    if [ -n "${EXPECTED_SERVICES:-}" ]; then
        printf "%s\n" "$EXPECTED_SERVICES" > "$INVENTORY_DIR/expected-services.txt" || {
            BACKUP_FILESYSTEM_INVENTORY_FAILURE="expected-services metadata"; return 1;
        }
    fi
    if ! "$compose_collector" "$SOURCE" > "$INVENTORY_DIR/compose-files.txt" 2>&1; then
        BACKUP_FILESYSTEM_INVENTORY_FAILURE="Compose-file discovery"
        return 1
    fi
    if ! "$size_collector" "$SOURCE" > "$INVENTORY_DIR/source-folder-sizes.txt" 2>&1; then
        BACKUP_FILESYSTEM_INVENTORY_FAILURE="source-size collection"
        return 1
    fi
    BACKUP_FILESYSTEM_INVENTORY_STATUS="success"
}

backup_generate_docker_inventory() {
    local docker_command="${1:-docker}" file runtime_failed=0
    local -a runtime_files=(containers.txt images.txt volumes.txt networks.txt docker-version.txt docker-info.txt)

    BACKUP_DOCKER_CLI_FOUND="no"
    BACKUP_DOCKER_DAEMON_REACHABLE="not applicable"
    BACKUP_DOCKER_INVENTORY_STATUS="unavailable"
    if ! command -v "$docker_command" >/dev/null 2>&1; then
        for file in "${runtime_files[@]}"; do
            backup_inventory_runtime_placeholder "$INVENTORY_DIR/$file" "Docker CLI unavailable" || return 1
        done
        return 0
    fi

    BACKUP_DOCKER_CLI_FOUND="yes"
    if backup_inventory_capture_docker "$INVENTORY_DIR/docker-info.txt" "$docker_command" info; then
        BACKUP_DOCKER_DAEMON_REACHABLE="yes"
    else
        BACKUP_DOCKER_DAEMON_REACHABLE="no"
        runtime_failed=1
    fi
    backup_inventory_capture_docker "$INVENTORY_DIR/containers.txt" "$docker_command" ps -a || runtime_failed=1
    backup_inventory_capture_docker "$INVENTORY_DIR/images.txt" "$docker_command" images || runtime_failed=1
    backup_inventory_capture_docker "$INVENTORY_DIR/volumes.txt" "$docker_command" volume ls || runtime_failed=1
    backup_inventory_capture_docker "$INVENTORY_DIR/networks.txt" "$docker_command" network ls || runtime_failed=1
    backup_inventory_capture_docker "$INVENTORY_DIR/docker-version.txt" "$docker_command" version || runtime_failed=1
    if [ "$runtime_failed" -eq 0 ]; then BACKUP_DOCKER_INVENTORY_STATUS="success"; else BACKUP_DOCKER_INVENTORY_STATUS="warning"; fi
}

backup_write_inventory_summary() {
    {
        echo "Project Phoenix Inventory"
        echo
        echo "Date: $(date)"
        echo "Host: $(hostname)"
        echo "Version: $VERSION"
        echo "Source: $SOURCE"
        echo "Original Source: $BACKUP_INVENTORY_ORIGINAL_SOURCE"
        echo "Expected Services Policy: $BACKUP_EXPECTED_SERVICES_POLICY"
        echo "Production Docker Recovery: $BACKUP_PRODUCTION_DOCKER_RECOVERY"
        echo "Destination: ${BACKUP_HOST}:${DESTINATION}"
        echo "Filesystem Inventory Status: $BACKUP_FILESYSTEM_INVENTORY_STATUS"
        echo "Docker Runtime Inventory Status: $BACKUP_DOCKER_INVENTORY_STATUS"
        echo "Docker CLI Found: $BACKUP_DOCKER_CLI_FOUND"
        echo "Docker Daemon Reachable: $BACKUP_DOCKER_DAEMON_REACHABLE"
        echo "Overall Inventory Status: $BACKUP_INVENTORY_STATUS"
        [ -z "${BACKUP_FILESYSTEM_INVENTORY_FAILURE:-}" ] || echo "Filesystem Inventory Failure: $BACKUP_FILESYSTEM_INVENTORY_FAILURE"
    } > "$INVENTORY_DIR/summary.txt"
}

backup_report_inventory_status() {
    case "${BACKUP_FILESYSTEM_INVENTORY_STATUS:-failed}" in
        success) log_success "Filesystem Inventory PASS" ;;
        *) log_error "Filesystem Inventory FAIL: ${BACKUP_FILESYSTEM_INVENTORY_FAILURE:-unknown failure}" ;;
    esac
    case "${BACKUP_DOCKER_INVENTORY_STATUS:-unavailable}" in
        success) log_success "Docker Runtime Inventory PASS" ;;
        unavailable) log_warning "Docker Runtime Inventory unavailable" ;;
        *) log_warning "Docker Runtime Inventory completed with warnings" ;;
    esac
    case "${BACKUP_METADATA_STATUS:-skipped}" in
        success) log_success "Metadata Publication PASS" ;;
        skipped) log_warning "Metadata publication skipped" ;;
        *) log_warning "Metadata Publication FAIL" ;;
    esac
}

generate_backup_inventory() {
    local docker_command="${1:-docker}"
    local compose_collector="${2:-backup_inventory_compose_files}"
    local size_collector="${3:-backup_inventory_source_sizes}"

    log_info "Generating inventory..."
    BACKUP_DOCKER_INVENTORY_STATUS="unavailable"
    BACKUP_DOCKER_CLI_FOUND="no"
    BACKUP_DOCKER_DAEMON_REACHABLE="not applicable"
    if ! backup_generate_filesystem_inventory "$compose_collector" "$size_collector"; then
        BACKUP_INVENTORY_STATUS="failed"
        backup_write_inventory_summary || true
        log_error "Filesystem Inventory FAIL: ${BACKUP_FILESYSTEM_INVENTORY_FAILURE:-unknown failure}"
        return 1
    fi
    backup_generate_docker_inventory "$docker_command" || BACKUP_DOCKER_INVENTORY_STATUS="warning"
    if [ "$BACKUP_DOCKER_INVENTORY_STATUS" = "success" ]; then BACKUP_INVENTORY_STATUS="success"; else BACKUP_INVENTORY_STATUS="warning"; fi
    backup_write_inventory_summary || {
        BACKUP_FILESYSTEM_INVENTORY_STATUS="failed"
        BACKUP_FILESYSTEM_INVENTORY_FAILURE="summary metadata"
        BACKUP_INVENTORY_STATUS="failed"
        log_error "Filesystem Inventory FAIL: summary metadata"
        return 1
    }
    log_success "Filesystem Inventory PASS"
    case "$BACKUP_DOCKER_INVENTORY_STATUS" in
        success) log_success "Docker Runtime Inventory PASS" ;;
        unavailable) log_warning "Docker Runtime Inventory unavailable" ;;
        *) log_warning "Docker Runtime Inventory completed with warnings" ;;
    esac
}
