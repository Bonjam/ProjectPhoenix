#!/bin/bash

setup_wizard() {
    setup_welcome
    setup_system_analysis
    setup_load_defaults
    setup_project
    setup_source
    setup_destination
    setup_ssh
    setup_confirm
    setup_write_config
    setup_test_connection
    setup_done
}

setup_system_analysis() {
    local discovered_path

    SETUP_DISCOVERED_DOCKER_SOURCES=()
    SETUP_DISCOVERED_SSH_KEYS=()

    section "SYSTEM ANALYSIS"
    echo
    printf 'Operating System : %s\n' "$(discovery_get_os_name)"
    printf 'Kernel           : %s\n' "$(discovery_get_kernel)"
    printf 'Architecture     : %s\n' "$(discovery_get_architecture)"
    echo

    echo "Required Tools"
    if discovery_has_command bash; then log_success "bash found"; else log_warning "bash not found"; fi
    if discovery_has_command ssh; then log_success "ssh found"; else log_warning "ssh not found"; fi
    if discovery_has_command rsync; then log_success "rsync found"; else log_warning "rsync not found"; fi
    echo

    echo "Docker"
    if discovery_has_docker; then log_success "Docker found"; else log_warning "Docker not found"; fi
    if discovery_has_docker_compose; then log_success "Docker Compose found"; else log_warning "Docker Compose not found"; fi
    echo

    while IFS= read -r discovered_path; do
        SETUP_DISCOVERED_SSH_KEYS+=("$discovered_path")
    done < <(discovery_find_ssh_keys)

    echo "SSH Keys"
    if [ "${#SETUP_DISCOVERED_SSH_KEYS[@]}" -eq 0 ]; then
        log_warning "No common SSH private keys found"
    else
        for discovered_path in "${SETUP_DISCOVERED_SSH_KEYS[@]}"; do
            log_success "Found: $discovered_path"
        done
    fi
    echo

    while IFS= read -r discovered_path; do
        SETUP_DISCOVERED_DOCKER_SOURCES+=("$discovered_path")
    done < <(discovery_find_common_docker_sources)

    echo "Docker Sources"
    if [ "${#SETUP_DISCOVERED_DOCKER_SOURCES[@]}" -eq 0 ]; then
        log_warning "No common Docker source folders found"
    else
        for discovered_path in "${SETUP_DISCOVERED_DOCKER_SOURCES[@]}"; do
            log_success "Found: $discovered_path"
        done
    fi

    echo
    echo "Continue with setup..."
}

setup_load_defaults() {
    load_config_if_exists >/dev/null 2>&1 || true

    SETUP_DEFAULT_PROJECT_NAME="${PROJECT_NAME:-Project Phoenix}"
    SETUP_DEFAULT_SOURCE="${SOURCE:-}"
    SETUP_DEFAULT_DESTINATION="${DESTINATION:-/mnt/backups/project-phoenix/}"
    SETUP_DEFAULT_BACKUP_HOST="${BACKUP_HOST:-backup-server.local}"
    SETUP_DEFAULT_BACKUP_USER="${BACKUP_USER:-backup}"
    SETUP_DEFAULT_SSH_KEY="${SSH_KEY:-}"
}

setup_path_in_list() {
    local expected_path="$1"
    shift
    local listed_path

    for listed_path in "$@"; do
        if [ "$listed_path" = "$expected_path" ]; then
            return 0
        fi
    done

    return 1
}

setup_welcome() {
    section "PROJECT PHOENIX SETUP"

    echo
    echo "Welcome to Project Phoenix."
    echo
    echo "Rise. Recover. Restore."
    echo
    echo "This wizard will configure your first backup."
    echo

    read -rp "Press ENTER to continue..."
}

setup_prompt_required() {
    local prompt="$1"
    local value=""

    while [ -z "$value" ]; do
        read -rp "$prompt" value

        if [ -z "$value" ]; then
            log_warning "A value is required"
        fi
    done

    printf '%s' "$value"
}

setup_prompt_absolute_path() {
    local prompt="$1"
    local default_value="${2:-}"
    local value=""

    while true; do
        if [ -n "$default_value" ]; then
            read -rp "$prompt [$default_value]: " value
            value="${value:-$default_value}"
        else
            read -rp "$prompt: " value
        fi

        case "$value" in
            /*)
                printf '%s' "$value"
                return 0
                ;;

            "")
                log_warning "A path is required"
                ;;

            *)
                log_warning "Please enter an absolute Linux path beginning with /"
                ;;
        esac
    done
}

setup_project() {
    echo
    section "PROJECT"

    read -rp "Project name [$SETUP_DEFAULT_PROJECT_NAME]: " SETUP_PROJECT_NAME
    SETUP_PROJECT_NAME="${SETUP_PROJECT_NAME:-$SETUP_DEFAULT_PROJECT_NAME}"
}

setup_source() {
    echo
    section "SOURCE"

    echo "What would you like to protect?"
    echo
    echo "1) Docker"
    echo "2) Custom folder"
    echo

    while true; do
        read -rp "Selection [1]: " SETUP_SOURCE_TYPE
        SETUP_SOURCE_TYPE="${SETUP_SOURCE_TYPE:-1}"

        case "$SETUP_SOURCE_TYPE" in
            1)
                setup_detect_docker_source
                break
                ;;

            2)
                SETUP_SOURCE=$(setup_prompt_absolute_path \
                    "Source folder" \
                    "$SETUP_DEFAULT_SOURCE")
                break
                ;;

            *)
                log_warning "Please choose 1 or 2"
                ;;
        esac
    done
}

setup_detect_docker_source() {
    local found=()
    local candidate
    local index
    local manual_option
    local selection

    echo
    echo "Scanning for common Docker folders..."
    echo

    if [ -n "$SETUP_DEFAULT_SOURCE" ]; then
        found+=("$SETUP_DEFAULT_SOURCE")
    fi

    for candidate in "${SETUP_DISCOVERED_DOCKER_SOURCES[@]}"; do
        if ! setup_path_in_list "$candidate" "${found[@]}"; then
            found+=("$candidate")
        fi
    done

    if [ "${#found[@]}" -eq 0 ]; then
        echo "No common Docker folder was detected."
        echo

        SETUP_SOURCE=$(setup_prompt_absolute_path \
            "Docker folder" \
            "${SETUP_DEFAULT_SOURCE:-/volume2/docker/}")

        return
    fi

    echo "Detected Docker folders:"
    echo

    index=1

    for candidate in "${found[@]}"; do
        echo "$index) $candidate"
        index=$((index + 1))
    done

    manual_option="$index"

    echo "$manual_option) Enter manually"
    echo

    while true; do
        read -rp "Selection [1]: " selection
        selection="${selection:-1}"

        if [[ "$selection" =~ ^[0-9]+$ ]] &&
            [ "$selection" -ge 1 ] &&
            [ "$selection" -le "${#found[@]}" ]; then

            SETUP_SOURCE="${found[$((selection - 1))]}"
            return
        fi

        if [ "$selection" = "$manual_option" ]; then
            SETUP_SOURCE=$(setup_prompt_absolute_path \
                "Docker folder" \
                "${SETUP_DEFAULT_SOURCE:-/volume2/docker/}")
            return
        fi

        log_warning "Please select one of the listed options"
    done
}

setup_destination() {
    echo
    section "DESTINATION"

    setup_backup_host
    setup_backup_user

    SETUP_DESTINATION=$(setup_prompt_absolute_path \
        "Destination path" \
        "$SETUP_DEFAULT_DESTINATION")
}

setup_backup_host() {
    local value=""

    while true; do
        read -rp "Backup host [$SETUP_DEFAULT_BACKUP_HOST]: " value
        value="${value:-$SETUP_DEFAULT_BACKUP_HOST}"

        if [[ "$value" =~ ^[A-Za-z0-9._:-]+$ ]]; then
            SETUP_BACKUP_HOST="$value"
            return
        fi

        log_warning "Enter a valid hostname or IP address without spaces"
    done
}

setup_backup_user() {
    local value=""

    while true; do
        read -rp "Backup user [$SETUP_DEFAULT_BACKUP_USER]: " value
        value="${value:-$SETUP_DEFAULT_BACKUP_USER}"

        if [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]]; then
            SETUP_BACKUP_USER="$value"
            return
        fi

        log_warning "Enter a valid SSH username without spaces"
    done
}

setup_ssh() {
    local default_key="$HOME/.ssh/id_ed25519"
    local discovered_key
    local entered_key=""
    local index
    local manual_option
    local selection
    local ssh_options=()

    echo
    section "SSH"

    if [ -n "$SETUP_DEFAULT_SSH_KEY" ]; then
        ssh_options+=("$SETUP_DEFAULT_SSH_KEY")
    fi

    for discovered_key in "${SETUP_DISCOVERED_SSH_KEYS[@]}"; do
        if ! setup_path_in_list "$discovered_key" "${ssh_options[@]}"; then
            ssh_options+=("$discovered_key")
        fi
    done

    if [ "${#ssh_options[@]}" -eq 1 ]; then
        default_key="${ssh_options[0]}"
    elif [ "${#ssh_options[@]}" -gt 1 ]; then
        echo "Available SSH keys:"
        echo

        index=1
        for discovered_key in "${ssh_options[@]}"; do
            echo "$index) $discovered_key"
            index=$((index + 1))
        done

        manual_option="$index"
        echo "$manual_option) Enter manually"
        echo

        while true; do
            read -rp "Selection [1]: " selection
            selection="${selection:-1}"

            if [[ "$selection" =~ ^[0-9]+$ ]] &&
                [ "$selection" -ge 1 ] &&
                [ "$selection" -le "${#ssh_options[@]}" ]; then

                entered_key="${ssh_options[$((selection - 1))]}"
                break
            fi

            if [ "$selection" = "$manual_option" ]; then
                break
            fi

            log_warning "Please select one of the listed options"
        done
    fi

    if [ -z "$entered_key" ]; then
        read -rp "SSH key location [$default_key]: " entered_key
        entered_key="${entered_key:-$default_key}"
    fi

    case "$entered_key" in
        \~/*)
            SETUP_SSH_KEY="$HOME/${entered_key#~/}"
            ;;

        /*)
            SETUP_SSH_KEY="$entered_key"
            ;;

        *)
            log_warning "SSH key path must be an absolute Linux path"
            SETUP_SSH_KEY="$default_key"
            log_info "Using default SSH key path: $SETUP_SSH_KEY"
            ;;
    esac

    if ssh_key_exists "$SETUP_SSH_KEY"; then
        log_success "SSH key found: $SETUP_SSH_KEY"
        return
    fi

    log_warning "SSH key not found: $SETUP_SSH_KEY"
    echo

    read -rp "Generate a new SSH key now? [Y/n]: " SETUP_GENERATE_KEY
    SETUP_GENERATE_KEY="${SETUP_GENERATE_KEY:-Y}"

    case "$SETUP_GENERATE_KEY" in
        Y|y|YES|yes)
            setup_generate_ssh_key
            ;;

        *)
            log_warning "Skipping SSH key generation"
            ;;
    esac
}

setup_generate_ssh_key() {
    if ssh_generate_key "$SETUP_SSH_KEY"; then
        log_success "SSH key generated: $SETUP_SSH_KEY"
        echo
        echo "Public key:"
        echo
        cat "${SETUP_SSH_KEY}.pub"
        echo
        echo "The public key must be authorised on the backup server."
    else
        log_error "Failed to generate SSH key"
        return 1
    fi
}

setup_confirm() {
    echo
    section "SUMMARY"

    echo "Project Name : $SETUP_PROJECT_NAME"
    echo "Source       : $SETUP_SOURCE"
    echo "Backup Host  : $SETUP_BACKUP_HOST"
    echo "Backup User  : $SETUP_BACKUP_USER"
    echo "Destination  : $SETUP_DESTINATION"
    echo "SSH Key      : $SETUP_SSH_KEY"
    echo

    read -rp "Write config.conf with these settings? [Y/n]: " SETUP_CONFIRM
    SETUP_CONFIRM="${SETUP_CONFIRM:-Y}"

    case "$SETUP_CONFIRM" in
        Y|y|YES|yes)
            ;;

        *)
            echo
            echo "Setup cancelled. No configuration was written."
            exit 0
            ;;
    esac
}

setup_write_config() {
    local config_file="$PROJECT_ROOT/config.conf"
    local backup_file

    if [ -f "$config_file" ]; then
        backup_file="$PROJECT_ROOT/config.conf.backup.$(date +%Y%m%d-%H%M%S)"

        if cp "$config_file" "$backup_file"; then
            log_warning "Existing config.conf backed up to: $backup_file"
        else
            log_error "Unable to back up the existing config.conf"
            return 1
        fi
    fi

    {
        echo "# Project Phoenix Configuration"
        echo "# Generated by phoenix setup"
        echo "# Generated: $(date)"
        echo

        printf 'PROJECT_NAME=%q\n' "$SETUP_PROJECT_NAME"
        printf 'TAGLINE=%q\n' "Rise. Recover. Restore."
        echo

        printf 'SOURCE=%q\n' "$SETUP_SOURCE"
        printf 'DESTINATION=%q\n' "$SETUP_DESTINATION"
        echo

        printf 'BACKUP_HOST=%q\n' "$SETUP_BACKUP_HOST"
        printf 'BACKUP_USER=%q\n' "$SETUP_BACKUP_USER"
        echo

        printf 'SSH_KEY=%q\n' "$SETUP_SSH_KEY"
        echo

        printf 'BACKUP_DIR=%q\n' "$PROJECT_ROOT"
        printf 'EXCLUDE_FILE=%q\n' "$PROJECT_ROOT/exclude.txt"
    } > "$config_file"

    log_success "Configuration written: $config_file"
}

setup_test_connection() {
    SETUP_SSH_READY="no"
    SETUP_DESTINATION_READY="no"

    echo
    section "CONNECTION TEST"

    if ! discovery_has_command ssh; then
        log_warning "SSH client is not installed"
        echo
        echo "Install OpenSSH before running a backup."
        return
    fi

    if ! ssh_key_exists "$SETUP_SSH_KEY"; then
        log_warning "SSH connection test skipped because the key does not exist"
        echo
        echo "Expected SSH key:"
        echo "  $SETUP_SSH_KEY"
        return
    fi

    echo "Testing SSH connection to:"
    echo "  ${SETUP_BACKUP_USER}@${SETUP_BACKUP_HOST}"
    echo

    if ssh_test_connection \
        "$SETUP_SSH_KEY" \
        "$SETUP_BACKUP_USER" \
        "$SETUP_BACKUP_HOST"; then

        SETUP_SSH_READY="yes"
        log_success "SSH connection successful"
        setup_test_remote_destination
    else
        log_warning "SSH connection was not established"
        echo
        echo "The configuration has still been saved."
        echo
        echo "To authorise this SSH key, run:"
        echo
        echo "  ssh-copy-id -i \"${SETUP_SSH_KEY}.pub\" \\"
        echo "    \"${SETUP_BACKUP_USER}@${SETUP_BACKUP_HOST}\""
        echo
        echo "You may be asked for the backup server password once."
        echo
        echo "After authorising the key, rerun:"
        echo
        echo "  bash scripts/phoenix.sh setup"
    fi
}

setup_test_remote_destination() {
    echo
    echo "Checking remote destination:"
    echo "  $SETUP_DESTINATION"
    echo

    if ssh_remote_destination_exists \
        "$SETUP_SSH_KEY" \
        "$SETUP_BACKUP_USER" \
        "$SETUP_BACKUP_HOST" \
        "$SETUP_DESTINATION"; then

        SETUP_DESTINATION_READY="yes"
        log_success "Remote destination exists"
    else
        log_warning "Remote destination was not found"
        echo
        echo "Create the directory on the backup server:"
        echo
        echo "  mkdir -p \"$SETUP_DESTINATION\""
        echo
        echo "Then confirm that ${SETUP_BACKUP_USER} can write to it."
    fi
}

setup_done() {
    echo
    section "SETUP COMPLETE"

    echo "Configuration : written"
    echo "SSH           : $SETUP_SSH_READY"
    echo "Destination   : $SETUP_DESTINATION_READY"
    echo

    if [ "$SETUP_SSH_READY" = "yes" ] &&
        [ "$SETUP_DESTINATION_READY" = "yes" ]; then

        log_success "Project Phoenix is ready for its first backup"
        echo
        echo "Run:"
        echo
        echo "  bash scripts/phoenix.sh backup"
    else
        log_warning "Project Phoenix needs additional connection setup"
        echo
        echo "Your configuration has been saved."
        echo "Complete the guidance above, then run setup again."
    fi

    echo
    echo "Configuration check:"
    echo
    echo "  bash scripts/phoenix.sh check-config"
}
