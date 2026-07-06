#!/bin/bash

write_history_entry() {
    local action="$1"
    local status="$2"
    local details="$3"

    HISTORY_DIR="$PROJECT_ROOT/history"
    HISTORY_FILE="$HISTORY_DIR/history.log"

    mkdir -p "$HISTORY_DIR"

    echo "$(date +"%Y-%m-%d %H:%M:%S") | $action | $status | $details" >> "$HISTORY_FILE"
}

show_history() {
    HISTORY_FILE="$PROJECT_ROOT/history/history.log"

    section "PROJECT PHOENIX HISTORY"

    if [ -f "$HISTORY_FILE" ]; then
        cat "$HISTORY_FILE"
    else
        log_warning "No history found yet"
    fi
}