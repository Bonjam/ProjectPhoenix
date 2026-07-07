#!/bin/bash

get_version() {
    if [ -f "$PROJECT_ROOT/VERSION" ]; then
        VERSION=$(cat "$PROJECT_ROOT/VERSION")
    else
        # shellcheck disable=SC2034
        VERSION="Development"
    fi
}