#!/bin/bash

run_discovery() {
    load_config
    get_version

    DISCOVERY_DIR="$PROJECT_ROOT/discovery"
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
        fi
        echo
        echo "Compose Files"
        echo "-------------"
        if [ -d "$SOURCE" ]; then
            find "$SOURCE" \
                \( -name "docker-compose.yml" -o \
                   -name "docker-compose.yaml" -o \
                   -name "compose.yml" -o \
                   -name "compose.yaml" \) \
                2>/dev/null
        else
            echo "Source folder not found: $SOURCE"
        fi
        echo
        echo "Storage"
        echo "-------"
        df -h "$SOURCE" 2>/dev/null || df -h
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
    } > "$DISCOVERY_FILE"

    log_success "Discovery report created: $DISCOVERY_FILE"
    echo
    cat "$DISCOVERY_FILE"
}