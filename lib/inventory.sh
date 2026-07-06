#!/bin/bash

run_inventory() {
    load_config

    INVENTORY_DIR="$PROJECT_ROOT/inventory"
    mkdir -p "$INVENTORY_DIR"

    INVENTORY_FILE="$INVENTORY_DIR/inventory.txt"

    section "PROJECT PHOENIX INVENTORY"

    log_info "Scanning source folder: $SOURCE"

    {
        echo "Project Phoenix Inventory"
        echo "Generated: $(date)"
        echo
        echo "Source:"
        echo "$SOURCE"
        echo
        echo "Source Size:"
        du -sh "$SOURCE" 2>/dev/null || echo "Unable to read source size"
        echo
        echo "Compose Files:"
        find "$SOURCE" \
            \( -name "docker-compose.yml" -o \
               -name "docker-compose.yaml" -o \
               -name "compose.yml" -o \
               -name "compose.yaml" \) \
            2>/dev/null || echo "No compose files found"
    } > "$INVENTORY_FILE"

    log_success "Inventory created: $INVENTORY_FILE"

    echo
    cat "$INVENTORY_FILE"
}