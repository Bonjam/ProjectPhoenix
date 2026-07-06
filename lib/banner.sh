#!/bin/bash

show_banner() {
    if [ -f "assets/ascii/phoenix.txt" ]; then
        cat "assets/ascii/phoenix.txt"
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
}