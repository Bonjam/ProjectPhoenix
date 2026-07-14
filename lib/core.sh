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
    echo "  phoenix.sh setup          Interactive setup wizard"
    echo "  phoenix.sh integrity-create Create a local integrity manifest"
    echo "  phoenix.sh integrity-verify Verify SOURCE against a manifest"
    echo "  phoenix.sh integrity-verify-remote Verify against copied remote reference"
    echo "  phoenix.sh integrity-fetch-remote Fetch latest remote reference read-only"
    echo "  phoenix.sh integrity-retention Analyse manifest retention read-only"
    echo "  phoenix.sh integrity-cleanup Confirm removal of old integrity manifests"
    echo "  phoenix.sh health          Run read-only end-to-end health checks"
    echo "  phoenix.sh destination-info Show the current destination profile"
    echo "  phoenix.sh source-info      Show the current source profile"
    echo "  phoenix.sh source-check     Check source access read-only"
    echo "  phoenix.sh local-check     Inspect a local destination read-only"
    echo "  phoenix.sh destination-migration Analyse legacy destination state"
    echo "  phoenix.sh destination-migrate Confirm copy-first legacy state migration"
    echo "  phoenix.sh backup         Run backup"
    echo "  phoenix.sh recover        Analyse backup recovery readiness"
    echo "  phoenix.sh restore        Show restore assistant"
    echo "  phoenix.sh restore-dry-run Preview files that would be restored"
    echo "  phoenix.sh restore-confirm Confirm and run a validated restore"
    echo "  phoenix.sh verify-restore Verify restored files read-only"
    echo
    echo "  phoenix.sh doctor         Run health diagnostics"
    echo "  phoenix.sh discovery      Discover system and Docker environment"
    echo "  phoenix.sh requirements   Check required system tools"
    echo "  phoenix.sh check-config   Validate configuration"
    echo "  phoenix.sh status         Show Project Phoenix status"
    echo
    echo "  phoenix.sh report         Generate text report"
    echo "  phoenix.sh html-report    Generate static HTML health report"
    echo "  phoenix.sh inventory      Generate source inventory"
    echo "  phoenix.sh confidence     Show recovery confidence score"
    echo "  phoenix.sh history        Show Project Phoenix history"
    echo
    echo "  phoenix.sh info           Show Project Phoenix core information"
    echo "  phoenix.sh banner         Show Project Phoenix banner"
    echo "  phoenix.sh test           Run lightweight test suite"
    echo "  phoenix.sh test-logging   Test the logging module"
    echo
}
