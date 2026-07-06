#!/bin/bash

run_restore() {
    load_config
    get_version

    section "PROJECT PHOENIX RESTORE"

    log_warning "Restore assistant is running in safe preview mode."
    echo

    echo "Version      : $VERSION"
    echo "Project      : $PROJECT_NAME"
    echo "Restore From : ${BACKUP_USER}@${BACKUP_HOST}:${DESTINATION}"
    echo "Restore To   : $SOURCE"
    echo

    section "RESTORE COMMAND"

    echo "rsync -avh -e \"ssh -i $SSH_KEY\" ${BACKUP_USER}@${BACKUP_HOST}:${DESTINATION} $SOURCE"
    echo

    section "AFTER RESTORE"

    echo "Find Compose files:"
    echo
    echo "find \"$SOURCE\" -name \"docker-compose.yml\" -o -name \"compose.yml\""
    echo

    echo "Start stacks from each Compose folder:"
    echo
    echo "docker compose up -d"
    echo

    log_success "Restore preview complete"
}