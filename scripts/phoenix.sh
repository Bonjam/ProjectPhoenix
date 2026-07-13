#!/bin/bash

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

source "$PROJECT_ROOT/lib/core.sh"
source "$PROJECT_ROOT/lib/module-loader.sh"

COMMAND="${1:-help}"

phoenix_init_core
case "$COMMAND" in
    help|--help|-h|check-config|destination-info|destination-migration|destination-migrate|health) ;;
    *) phoenix_init_dirs ;;
esac
load_phoenix_modules


case "$COMMAND" in

    backup)
        show_banner
        if run_backup; then
            backup_exit_code=0
        else
            backup_exit_code=$?
        fi
        write_history_entry "backup" \
            "${BACKUP_HISTORY_STATUS:-failed}" \
            "${BACKUP_HISTORY_DETAILS:-Backup engine stopped before completion}"
        exit "$backup_exit_code"
        ;;

    destination-migrate)
        show_banner
        run_destination_migrate
        ;;

    destination-info)
        show_banner
        run_destination_info
        ;;

    destination-migration)
        show_banner
        run_destination_migration
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

    health)
        show_banner
        run_health
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

    integrity-create)
        show_banner
        run_integrity_create
        ;;

    integrity-verify)
        show_banner
        run_integrity_verify "${2:-}"
        ;;

    integrity-verify-remote)
        show_banner
        run_integrity_verify_remote
        ;;

    integrity-fetch-remote)
        show_banner
        run_integrity_fetch_remote
        ;;

    integrity-retention)
        show_banner
        run_integrity_retention
        ;;

    integrity-cleanup)
        show_banner
        run_integrity_cleanup
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

    restore-dry-run)
        show_banner
        run_restore_dry_run
        ;;

    restore-confirm)
        show_banner
        run_restore_confirm
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

    verify-restore)
        show_banner
        run_verify_restore
        ;;

    *)
        show_banner
        echo "Unknown command: $COMMAND"
        echo
        phoenix_print_usage
        exit 1
        ;;
esac
