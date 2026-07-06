#!/bin/bash

run_report() {
    load_config
    get_version

    REPORT_DIR="$PROJECT_ROOT/reports"
    mkdir -p "$REPORT_DIR"

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
        echo "Destination  : ${BACKUP_USER}@${BACKUP_HOST}:${DESTINATION}"
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