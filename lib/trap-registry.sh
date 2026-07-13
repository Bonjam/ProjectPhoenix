#!/bin/bash

declare -Ag PHOENIX_TRAP_HANDLERS=()
declare -Ag PHOENIX_TRAP_INSTALLED=()

phoenix_trap_previous_command() {
    local signal_name="$1" declaration payload previous_command

    declaration=$(trap -p "$signal_name")
    [ -n "$declaration" ] || return 1
    payload="${declaration#trap -- }"
    payload="${payload% *}"
    eval "previous_command=$payload"
    printf "%s\n" "$previous_command"
}

phoenix_trap_dispatch() {
    local signal_name="$1" key command
    local -a handler_keys=()

    for key in "${!PHOENIX_TRAP_HANDLERS[@]}"; do
        [[ "$key" == "$signal_name:"* ]] && handler_keys+=("$key")
    done
    for key in "${handler_keys[@]}"; do
        command="${PHOENIX_TRAP_HANDLERS[$key]:-}"
        [ -z "$command" ] || eval "$command"
    done
}

phoenix_trap_install_dispatcher() {
    local signal_name="$1" previous_command

    [ "${PHOENIX_TRAP_INSTALLED[$signal_name]:-no}" = "yes" ] && return 0
    if previous_command=$(phoenix_trap_previous_command "$signal_name"); then
        PHOENIX_TRAP_HANDLERS["$signal_name:existing"]="$previous_command"
    fi
    case "$signal_name" in
        EXIT) trap 'phoenix_trap_dispatch EXIT' EXIT ;;
        INT) trap 'phoenix_trap_dispatch INT; exit 130' INT ;;
        TERM) trap 'phoenix_trap_dispatch TERM; exit 143' TERM ;;
        HUP) trap 'phoenix_trap_dispatch HUP; exit 129' HUP ;;
        *) return 1 ;;
    esac
    PHOENIX_TRAP_INSTALLED["$signal_name"]="yes"
}

phoenix_trap_register() {
    local handler_id="$1" command="$2" signal_name
    shift 2

    [[ "$handler_id" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
    [ "$#" -gt 0 ] || return 1
    for signal_name in "$@"; do
        phoenix_trap_install_dispatcher "$signal_name" || return 1
        PHOENIX_TRAP_HANDLERS["$signal_name:$handler_id"]="$command"
    done
}

phoenix_trap_unregister() {
    local handler_id="$1" signal_name
    shift

    for signal_name in "$@"; do
        unset 'PHOENIX_TRAP_HANDLERS['"$signal_name:$handler_id"']'
    done
}
