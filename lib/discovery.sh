#!/bin/bash

discovery_get_os_name() {
    if [ -r /etc/os-release ]; then
        (
            # shellcheck disable=SC1091
            . /etc/os-release
            printf '%s\n' "${PRETTY_NAME:-${NAME:-Unknown Linux}}"
        )
    else
        uname -a
    fi
}

discovery_get_kernel() {
    uname -r
}

discovery_get_architecture() {
    uname -m
}

discovery_has_command() {
    command -v "$1" >/dev/null 2>&1
}

discovery_has_docker() {
    discovery_has_command docker
}

discovery_has_docker_compose() {
    discovery_get_docker_compose_version >/dev/null 2>&1
}

discovery_get_docker_compose_version() {
    if discovery_has_docker && docker compose version >/dev/null 2>&1; then
        docker compose version
    elif discovery_has_command docker-compose; then
        docker-compose --version
    else
        return 1
    fi
}

discovery_find_ssh_keys() {
    local ssh_dir="${1:-$HOME/.ssh}"

    [ -d "$ssh_dir" ] || return 0

    find "$ssh_dir" -maxdepth 1 -type f \
        \( -name 'id_rsa' -o -name 'id_ecdsa' -o \
           -name 'id_ed25519' -o -name 'id_dsa' \) \
        2>/dev/null
}

discovery_find_common_docker_sources() {
    local candidate

    if [ "$#" -eq 0 ]; then
        set -- "/srv/docker" "/opt/docker" "/home/$USER/docker" \
            "/mnt/docker" "/volume1/docker" "/volume2/docker"
    fi

    for candidate in "$@"; do
        if [ -d "$candidate" ]; then
            printf '%s\n' "$candidate"
        fi
    done
}

discovery_get_storage_summary() {
    df -h
}

discovery_get_memory_summary() {
    free -h 2>/dev/null
}

discovery_get_cpu_summary() {
    if ! discovery_has_command lscpu; then
        return 1
    fi

    lscpu | grep -E "Model name|Architecture|CPU\(s\)" 2>/dev/null || true
}

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
        discovery_get_os_name
        echo

        echo "Kernel"
        echo "------"
        discovery_get_kernel
        echo

        echo "Architecture"
        echo "------------"
        discovery_get_architecture
        echo

        echo "Core Tools"
        echo "----------"
        discovery_has_command bash && echo "bash: found" || echo "bash: missing"
        discovery_has_command ssh && echo "ssh: found" || echo "ssh: missing"
        discovery_has_command rsync && echo "rsync: found" || echo "rsync: missing"
        echo

        echo "Docker"
        echo "------"
        if discovery_has_docker; then
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
        discovery_get_docker_compose_version || echo "Docker Compose installed: no"
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
        discovery_get_storage_summary
        echo

        echo "Memory"
        echo "------"
        discovery_get_memory_summary || echo "Memory information unavailable"
        echo

        echo "CPU"
        echo "---"
        discovery_get_cpu_summary || echo "CPU information unavailable"
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
