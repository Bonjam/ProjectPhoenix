#!/bin/bash

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

source "$PROJECT_ROOT/lib/banner.sh"
source "$PROJECT_ROOT/lib/config.sh"

case "$1" in
    banner)
        show_banner
        ;;
    check-config)
        load_config
        echo "Configuration loaded successfully."
        echo "Project: $PROJECT_NAME"
        echo "Source : $SOURCE"
        echo "Target : ${BACKUP_USER}@${BACKUP_HOST}:${DESTINATION}"
        ;;
    *)
        show_banner
        echo "Usage:"
        echo "  phoenix.sh banner        Show Project Phoenix banner"
        echo "  phoenix.sh check-config  Validate configuration"
        ;;
esac