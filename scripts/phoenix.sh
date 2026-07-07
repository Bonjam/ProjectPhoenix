#!/bin/bash

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

source "$PROJECT_ROOT/lib/version.sh"
source "$PROJECT_ROOT/lib/banner.sh"
source "$PROJECT_ROOT/lib/config.sh"
source "$PROJECT_ROOT/lib/logging.sh"
source "$PROJECT_ROOT/lib/validator.sh"
source "$PROJECT_ROOT/lib/history.sh"
source "$PROJECT_ROOT/lib/confidence.sh"
source "$PROJECT_ROOT/lib/discovery.sh"
source "$PROJECT_ROOT/lib/inventory.sh"
source "$PROJECT_ROOT/lib/status.sh"
source "$PROJECT_ROOT/lib/backup.sh"
source "$PROJECT_ROOT/lib/doctor.sh"
source "$PROJECT_ROOT/lib/restore.sh"
source "$PROJECT_ROOT/lib/report.sh"
source "$PROJECT_ROOT/lib/html-report.sh"
source "$PROJECT_ROOT/lib/test.sh"
source "$PROJECT_ROOT/lib/requirements.sh"

case "$1" in

    banner)
        show_banner
        ;;

    check-config)
        show_banner
        validate_config
        ;;

    confidence)
        show_banner
        calculate_confidence
        write_history_entry "confidence" "completed" "Recovery confidence calculated"
        ;;

    discovery)
        show_banner
        run_discovery
        write_history_entry "discovery" "success" "Environment discovery completed"
        ;;

    history)
        show_banner
        show_history
        ;;

    html-report)
        show_banner
        generate_html_report
        write_history_entry "html-report" "success" "HTML health report generated"
        ;;

    inventory)
        show_banner
        run_inventory
        write_history_entry "inventory" "success" "Inventory generated"
        ;;

    requirements)
        show_banner
        check_requirements
        ;;

    status)
        show_banner
        run_status
        ;;

    backup)
        show_banner
        run_backup
        write_history_entry "backup" "completed" "Backup engine executed"
        ;;

    doctor)
        show_banner
        run_doctor
        write_history_entry "doctor" "completed" "Doctor diagnostics executed"
        ;;

    restore)
        show_banner
        run_restore
        write_history_entry "restore" "preview" "Restore preview displayed"
        ;;

    report)
        show_banner
        run_report
        write_history_entry "report" "success" "Text report generated"
        ;;

    test)
        show_banner
        run_tests
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
        echo
        ;;
esac