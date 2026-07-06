#!/bin/bash

log_info() {
    echo "[INFO] $1"
}

log_success() {
    echo "[PASS] $1"
}

log_warning() {
    echo "[WARN] $1"
}

log_error() {
    echo "[FAIL] $1"
}

section() {
    echo
    echo "============================================================="
    echo "$1"
    echo "============================================================="
}