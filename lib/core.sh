#!/bin/bash

phoenix_init_core() {
    # shellcheck disable=SC2034
    PROJECT_NAME="Project Phoenix"

    # shellcheck disable=SC2034
    PROJECT_TAGLINE="Rise. Recover. Restore."

    # shellcheck disable=SC2034
    PROJECT_CODENAME="Wings of Recovery"

    # shellcheck disable=SC2034
    VERSION_FILE="$PROJECT_ROOT/VERSION"

    LOG_DIR="$PROJECT_ROOT/logs"
    STATUS_DIR="$PROJECT_ROOT/status"
    HISTORY_DIR="$PROJECT_ROOT/history"
    REPORT_DIR="$PROJECT_ROOT/reports"
    MANIFEST_DIR="$PROJECT_ROOT/manifests"
    INVENTORY_DIR="$PROJECT_ROOT/inventory"
    DISCOVERY_DIR="$PROJECT_ROOT/discovery"
}

phoenix_init_dirs() {
    mkdir -p "$LOG_DIR" "$STATUS_DIR" "$HISTORY_DIR" "$REPORT_DIR" "$MANIFEST_DIR" "$INVENTORY_DIR" "$DISCOVERY_DIR"
}

phoenix_print_usage() {
    echo "Usage:"
    echo
    echo "  phoenix.sh backup          Run backup"
    echo "  phoenix.sh banner          Show Project Phoenix banner"
    echo "  phoenix.sh check-config    Validate configuration"
    echo "  phoenix.sh confidence      Show recovery confidence score"
    echo "  phoenix.sh discovery       Discover system and Docker environment"
    echo "  phoenix.sh doctor          Run health diagnostics"
    echo "  phoenix.sh history         Show Project Phoenix history"
    echo "  phoenix.sh html-report     Generate static HTML health report"
    echo "  phoenix.sh inventory       Generate source inventory"
    echo "  phoenix.sh report          Generate text report"
    echo "  phoenix.sh requirements    Check required system tools"
    echo "  phoenix.sh restore         Show restore assistant"
    echo "  phoenix.sh status          Show Project Phoenix status"
    echo "  phoenix.sh test            Run lightweight test suite"
    echo "  phoenix.sh test-logging    Test the logging module"
    echo "  phoenix.sh info            Show Project Phoenix core information"
    echo
}