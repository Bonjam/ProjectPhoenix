#!/bin/bash

run_info() {
    get_version

    section "PROJECT PHOENIX INFO"

    echo "Name        : $PROJECT_NAME"
    echo "Tagline     : $PROJECT_TAGLINE"
    echo "Version     : $VERSION"
    echo "Codename    : $PROJECT_CODENAME"
    echo "Root        : $PROJECT_ROOT"
    echo
    echo "Directories:"
    echo "  Logs      : $LOG_DIR"
    echo "  Status    : $STATUS_DIR"
    echo "  History   : $HISTORY_DIR"
    echo "  Reports   : $REPORT_DIR"
    echo "  Manifests : $MANIFEST_DIR"
    echo "  Inventory : $INVENTORY_DIR"
    echo "  Discovery : $DISCOVERY_DIR"
}