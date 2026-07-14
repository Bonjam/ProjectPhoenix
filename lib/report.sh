#!/bin/bash

run_report() {
    load_config
    get_version

    REPORT_DIR="$DESTINATION_REPORT_DIR"
    destination_prepare_directory "$REPORT_DIR" || return 1

    REPORT_FILE="$REPORT_DIR/latest-report.txt"

    section "PROJECT PHOENIX REPORT"

    {
        echo "Project Phoenix Report"
        echo "======================"
        echo
        echo "Version      : $VERSION"
        echo "Generated    : $(date)"
        echo "Project      : $PROJECT_NAME"
        echo "Source       : $SOURCE"
        echo "Destination  : $(destination_endpoint_summary)"
        echo "Destination ID: $DESTINATION_ID"
        echo "Destination Name: $DESTINATION_NAME"
        echo "Transport    : $DESTINATION_TRANSPORT"
        echo "Filesystem   : $(transport_call filesystem_summary)"
        echo
        echo "Source Size:"
        du -sh "$SOURCE" 2>/dev/null || echo "Unable to read source size"
        echo
        echo "Inventory:"
        if [ -f "$PROJECT_ROOT/inventory/inventory.txt" ]; then
            echo "Inventory exists"
        else
            echo "No inventory found"
        fi
    } > "$REPORT_FILE"

    log_success "Report generated: $REPORT_FILE"

    echo
    cat "$REPORT_FILE"
}
