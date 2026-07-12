#!/bin/bash

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

source "$PROJECT_ROOT/lib/core.sh"
source "$PROJECT_ROOT/lib/module-loader.sh"

phoenix_init_core
phoenix_init_dirs
load_phoenix_modules

COMMAND="$1"

if [ -z "$COMMAND" ]; then
    COMMAND="help"
fi

case "$COMMAND" in

    backup)
        show_banner
        run_backup
        write_history_entry "backup" "completed" "Backup engine executed"
        ;;

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

    doctor)
        show_banner
        run_doctor
        write_history_entry "doctor" "completed" "Doctor diagnostics executed"
        ;;

    help|--help|-h)
        show_banner
        phoenix_print_usage
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

    info)
        show_banner
        run_info
        ;;

    inventory)
        show_banner
        run_inventory
        write_history_entry "inventory" "success" "Inventory generated"
        ;;

    report)
        show_banner
        run_report
        write_history_entry "report" "success" "Text report generated"
        ;;

    recover)
        show_banner
        run_recovery
        ;;

    requirements)
        show_banner
        check_requirements
        ;;

    restore)
        show_banner
        run_restore
        write_history_entry "restore" "preview" "Restore preview displayed"
        ;;

    setup)
        show_banner
        setup_wizard
        write_history_entry "setup" "started" "Interactive setup wizard launched"
        ;;

    status)
        show_banner
        run_status
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
        echo "Unknown command: $COMMAND"
        echo
        phoenix_print_usage
        exit 1
        ;;
esac
