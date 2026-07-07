#!/bin/bash

run_discovery() {
    get_version

    DISCOVERY_FILE="$DISCOVERY_DIR/discovery.txt"

    mkdir -p "$DISCOVERY_DIR"

    section "PROJECT PHOENIX DISCOVERY"

    {
        echo "Project Phoenix Discovery Report"
        echo "================================"
        echo
        echo "Generated : $(date)"
        echo "Version   : $VERSION"
        echo "Hostname  : $(hostname)"
        echo

        echo "Operating System"
        echo "----------------"
        if [ -f /etc/os-release ]; then
            grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"'
        else
            uname -a
        fi
        echo

        echo "Kernel"
        echo "------"
        uname -r
        echo

        echo "Architecture"
        echo "------------"
        uname -m
        echo

        echo "Core Tools"
        echo "----------"
        command -v bash >/dev/null 2>&1 && echo "bash: found" || echo "bash: missing"
        command -v ssh >/dev/null 2>&1 && echo "ssh: found" || echo "ssh: missing"
        command -v rsync >/dev/null 2>&1 && echo "rsync: found" || echo "rsync: missing"
        echo

        echo "Docker"
        echo "------"
        if command -v docker >/dev/null 2>&1; then
            echo "Docker installed: yes"
            docker --version 2>/dev/null
            echo

            echo "Containers:"
            docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null
            echo

            echo "Images:"
            docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" 2>/dev/null
            echo

            echo "Volumes:"
            docker volume ls 2>/dev/null
            echo

            echo "Networks:"
            docker network ls 2>/dev/null
        else
            echo "Docker installed: no"
            echo "Docker discovery skipped."
        fi
        echo

        echo "Docker Compose"
        echo "--------------"
        if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
            docker compose version
        elif command -v docker-compose >/dev/null 2>&1; then
            docker-compose --version
        else
            echo "Docker Compose installed: no"
        fi
        echo

        echo "Common Docker Folder Candidates"
        echo "-------------------------------"
        for candidate in \
            "/srv/docker" \
            "/opt/docker" \
            "/home/$USER/docker" \
            "/mnt/docker" \
            "/volume1/docker" \
            "/volume2/docker"
        do
            if [ -d "$candidate" ]; then
                echo "FOUND: $candidate"
            else
                echo "not found: $candidate"
            fi
        done
        echo

        echo "Compose Files Under Current Project"
        echo "-----------------------------------"
        find "$PROJECT_ROOT" \
            \( -name "docker-compose.yml" -o \
               -name "docker-compose.yaml" -o \
               -name "compose.yml" -o \
               -name "compose.yaml" \) \
            2>/dev/null || true
        echo

        echo "Storage"
        echo "-------"
        df -h
        echo

        echo "Memory"
        echo "------"
        free -h 2>/dev/null || echo "Memory information unavailable"
        echo

        echo "CPU"
        echo "---"
        if command -v lscpu >/dev/null 2>&1; then
            lscpu | grep -E "Model name|Architecture|CPU\(s\)" 2>/dev/null
        else
            echo "CPU information unavailable"
        fi
        echo

        echo "Suggested Next Step"
        echo "-------------------"
        echo "Create a config file with:"
        echo "cp examples/config.example.conf config.conf"
        echo
        echo "Then edit config.conf with your real source and backup destination."
    } > "$DISCOVERY_FILE"

    log_success "Discovery report created: $DISCOVERY_FILE"
    echo
    cat "$DISCOVERY_FILE"
}