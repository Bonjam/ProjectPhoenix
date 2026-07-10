#!/bin/bash

setup_wizard() {
    setup_welcome
    setup_project
    setup_source
    setup_destination
    setup_ssh
    setup_confirm
    setup_write_config
    setup_test_connection
    setup_done
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

    read -rp "Project name [Project Phoenix]: " SETUP_PROJECT_NAME
    SETUP_PROJECT_NAME="${SETUP_PROJECT_NAME:-Project Phoenix}"
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
                SETUP_SOURCE=$(setup_prompt_absolute_path "Source folder")
                break
                ;;

            *)
                log_warning "Please choose 1 or 2"
                ;;
        esac
    done
}

setup_detect_docker_source() {
    local candidates=(
        "/volume2/docker/"
        "/volume1/docker/"
        "/srv/docker/"
        "/opt/docker/"
        "/mnt/docker/"
        "$HOME/docker/"
    )

    local found=()
    local candidate
    local index
    local manual_option
    local selection

    echo
    echo "Scanning for common Docker folders..."
    echo

    for candidate in "${candidates[@]}"; do
        if [ -d "$candidate" ]; then
            found+=("$candidate")
        fi
    done

    if [ "${#found[@]}" -eq 0 ]; then
        echo "No common Docker folder was detected."
        echo

        SETUP_SOURCE=$(setup_prompt_absolute_path \
            "Docker folder" \
            "/volume2/docker/")

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
                "/volume2/docker/")
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
        "/mnt/backups/project-phoenix/")
}

setup_backup_host() {
    local value=""

    while true; do
        read -rp "Backup host [backup-server.local]: " value
        value="${value:-backup-server.local}"

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
        read -rp "Backup user [backup]: " value
        value="${value:-backup}"

        if [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]]; then
            SETUP_BACKUP_USER="$value"
            return
        fi

        log_warning "Enter a valid SSH username without spaces"
    done
}

setup_ssh() {
    local default_key="$HOME/.ssh/id_ed25519"
    local entered_key=""

    echo
    section "SSH"

    read -rp "SSH key location [$default_key]: " entered_key
    entered_key="${entered_key:-$default_key}"

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

    if [ -f "$SETUP_SSH_KEY" ]; then
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
    if ! command -v ssh-keygen >/dev/null 2>&1; then
        log_error "ssh-keygen is not installed"
        return 1
    fi

    mkdir -p "$(dirname "$SETUP_SSH_KEY")"

    if ssh-keygen \
        -t ed25519 \
        -f "$SETUP_SSH_KEY" \
        -N "" \
        -C "project-phoenix" \
        >/dev/null 2>&1; then

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

    if ! command -v ssh >/dev/null 2>&1; then
        log_warning "SSH client is not installed"
        echo
        echo "Install OpenSSH before running a backup."
        return
    fi

    if [ ! -f "$SETUP_SSH_KEY" ]; then
        log_warning "SSH connection test skipped because the key does not exist"
        echo
        echo "Expected SSH key:"
        echo "  $SETUP_SSH_KEY"
        return
    fi

    echo "Testing SSH connection to:"
    echo "  ${SETUP_BACKUP_USER}@${SETUP_BACKUP_HOST}"
    echo

    if ssh \
        -i "$SETUP_SSH_KEY" \
        -o BatchMode=yes \
        -o ConnectTimeout=8 \
        -o StrictHostKeyChecking=accept-new \
        "${SETUP_BACKUP_USER}@${SETUP_BACKUP_HOST}" \
        "printf '%s\n' PROJECT_PHOENIX_SSH_OK" \
        2>/dev/null |
        grep -q "PROJECT_PHOENIX_SSH_OK"; then

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
    local remote_destination

    echo
    echo "Checking remote destination:"
    echo "  $SETUP_DESTINATION"
    echo

    printf -v remote_destination '%q' "$SETUP_DESTINATION"

    if ssh \
        -i "$SETUP_SSH_KEY" \
        -o BatchMode=yes \
        -o ConnectTimeout=8 \
        "${SETUP_BACKUP_USER}@${SETUP_BACKUP_HOST}" \
        "test -d $remote_destination" \
        >/dev/null 2>&1; then

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