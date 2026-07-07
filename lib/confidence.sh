#!/bin/bash

calculate_confidence() {
    load_config

    SCORE=0
    MAX_SCORE=5

    section "PROJECT PHOENIX RECOVERY CONFIDENCE"

    if [ -f "$PROJECT_ROOT/VERSION" ]; then
        log_success "Version file present"
        SCORE=$((SCORE + 1))
    else
        log_error "Version file missing"
    fi

    if [ -f "$PROJECT_ROOT/lib/backup.sh" ]; then
        log_success "Backup module present"
        SCORE=$((SCORE + 1))
    else
        log_error "Backup module missing"
    fi

    if [ -f "$PROJECT_ROOT/lib/restore.sh" ]; then
        log_success "Restore module present"
        SCORE=$((SCORE + 1))
    else
        log_error "Restore module missing"
    fi

    if [ -f "$PROJECT_ROOT/lib/inventory.sh" ]; then
        log_success "Inventory module present"
        SCORE=$((SCORE + 1))
    else
        log_error "Inventory module missing"
    fi

    if [ -n "${SOURCE:-}" ]; then
        log_success "Source configured"
        SCORE=$((SCORE + 1))
    else
        log_error "Source missing"
    fi

    echo
    PERCENT=$((SCORE * 100 / MAX_SCORE))

    echo "Score      : $SCORE / $MAX_SCORE"
    echo "Confidence : $PERCENT%"
    echo

    if [ "$PERCENT" -ge 80 ]; then
        echo "Status     : READY FOR DISASTER RECOVERY"
    elif [ "$PERCENT" -ge 50 ]; then
        echo "Status     : PARTIALLY READY"
    else
        echo "Status     : NOT READY"
    fi
}