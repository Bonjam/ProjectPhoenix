#!/bin/bash

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

source "$PROJECT_ROOT/lib/version.sh"
source "$PROJECT_ROOT/lib/banner.sh"
source "$PROJECT_ROOT/lib/config.sh"
source "$PROJECT_ROOT/lib/logging.sh"
source "$PROJECT_ROOT/lib/validator.sh"
source "$PROJECT_ROOT/lib/inventory.sh"
source "$PROJECT_ROOT/lib/status.sh"
source "$PROJECT_ROOT/lib/backup.sh"
source "$PROJECT_ROOT/lib/doctor.sh"
source "$PROJECT_ROOT/lib/restore.sh"
source "$PROJECT_ROOT/lib/report.sh"

case "$1" in

    banner)
        show_banner
        ;;

    check-config)
        show_banner
        validate_config
        ;;

    inventory)
        show_banner
        run_inventory
        ;;

    status)
        show_banner
        run_status
        ;;

    backup)
        show_banner
        run_backup
        ;;

    doctor)
        show_banner
        run_doctor
        ;;

    restore)
        show_banner
        run_restore
        ;;

    report)
        show_banner
        run_report
        ;;

    test-logging)
        show_banner
        section "PROJECT PHOENIX LOGGING TEST"
        log_info "Starting logging test"
        log_success "Everything is working"
        log_warning "Example warning"
        log_error "Example error"
        ;;

    *)
        show_banner
        echo "Usage:"
        echo
        echo "  phoenix.sh backup          Run backup"
        echo "  phoenix.sh banner          Show Project Phoenix banner"
        echo "  phoenix.sh check-config    Validate configuration"
        echo "  phoenix.sh doctor          Run health diagnostics"
        echo "  phoenix.sh inventory       Generate source inventory"
        echo "  phoenix.sh report          Generate text report"
        echo "  phoenix.sh restore         Show restore assistant"
        echo "  phoenix.sh status          Show Project Phoenix status"
        echo "  phoenix.sh test-logging    Test the logging module"
        echo
        ;;
esac