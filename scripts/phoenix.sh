#!/bin/bash

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

source "$PROJECT_ROOT/lib/banner.sh"

case "$1" in
    banner)
        show_banner
        ;;
    *)
        show_banner
        echo "Usage:"
        echo "  phoenix.sh banner   Show Project Phoenix banner"
        ;;
esac