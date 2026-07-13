#!/bin/bash

write_history_entry() {
    local action="$1"
    local status="$2"
    local details="$3"
    local destination_metadata

    if [ -z "${DESTINATION_HISTORY_DIR:-}" ]; then
        if ! load_config_if_exists >/dev/null 2>&1; then
            destination_resolve_context || return 1
        fi
    fi
    HISTORY_FILE="$DESTINATION_HISTORY_DIR/history.log"
    destination_metadata=$(printf "destination_id=%q; destination_name=%q; transport=%q; endpoint=%q" \
        "$DESTINATION_ID" "$DESTINATION_NAME" "$DESTINATION_TRANSPORT" \
        "$(destination_endpoint_summary)")

    destination_prepare_directory "$DESTINATION_HISTORY_DIR" || return 1

    echo "$(date +"%Y-%m-%d %H:%M:%S") | $action | $status | $details; $destination_metadata" >> "$HISTORY_FILE"
}

show_history() {
    load_config_if_exists >/dev/null 2>&1 || destination_resolve_context || return 1
    destination_select_history_file
    HISTORY_FILE="$DESTINATION_SELECTED_HISTORY_FILE"

    section "PROJECT PHOENIX HISTORY"

    if [ -f "$HISTORY_FILE" ]; then
        if [ "$DESTINATION_HISTORY_STATE_SOURCE" = "legacy" ]; then
            log_warning "Using legacy history for the default destination; namespaced and legacy history are not combined"
        fi
        cat "$HISTORY_FILE"
    else
        log_warning "No history found yet"
    fi
}
