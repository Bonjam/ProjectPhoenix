#!/bin/bash

get_version() {
    if [ -f "$PROJECT_ROOT/VERSION" ]; then
        VERSION=$(cat "$PROJECT_ROOT/VERSION")
    else
        VERSION="Development"
    fi
}