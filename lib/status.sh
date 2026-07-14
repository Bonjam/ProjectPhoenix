#!/bin/bash

run_status() {
    load_config
    get_version

    section "PROJECT PHOENIX STATUS"

    echo "Version      : $VERSION"
    echo "Project      : $PROJECT_NAME"
    echo "Host         : $(hostname)"
    echo "Source       : $SOURCE"
    echo "Destination  : $(destination_endpoint_summary)"
    echo "Destination ID: $DESTINATION_ID"
    echo "Transport    : $DESTINATION_TRANSPORT"
    echo "Filesystem   : $(transport_call filesystem_summary)"
    echo

    echo "Local Source:"
    du -sh "$SOURCE" 2>/dev/null || echo "Unable to read source"
    echo

    echo "Inventory:"
    if [ -f "$PROJECT_ROOT/inventory/inventory.txt" ]; then
        log_success "Inventory exists"
        echo "File: $PROJECT_ROOT/inventory/inventory.txt"
    else
        log_warning "No inventory found yet"
        echo "Run: phoenix.sh inventory"
    fi

    echo
    echo "Configuration:"
    log_success "Configuration loaded"
}
