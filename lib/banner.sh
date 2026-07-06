#!/bin/bash

show_banner() {

    source "$PROJECT_ROOT/lib/version.sh"
    get_version

    if [ -f "$PROJECT_ROOT/assets/ascii/phoenix.txt" ]; then
        cat "$PROJECT_ROOT/assets/ascii/phoenix.txt"
    else
        echo "PROJECT PHOENIX"
        echo "Rise. Recover. Restore."
    fi

    echo
    echo "============================================================="
    echo "        PROJECT PHOENIX - Docker Disaster Recovery"
    echo "                Rise. Recover. Restore."
    echo "============================================================="
    echo
    echo "Version : $VERSION"
    echo
}