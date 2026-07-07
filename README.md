# 🦅 Project Phoenix

> Rise. Recover. Restore.

Lightweight disaster recovery toolkit for Docker configuration backups using SSH and rsync.

It is designed to help homelab users, NAS users, Raspberry Pi users, and self-hosters back up important Docker configuration folders to another machine using `rsync` over SSH.

Status: Alpha

Platform: Linux

Language: Bash

Transport: SSH + rsync

License: MIT

## Goal

Project Phoenix is not trying to be a heavy enterprise backup platform.

Its goal is simple:

> Help you recover your Docker configs when something goes wrong.

This is especially useful for services that take time to tune, such as:

- Sonarr
- Radarr
- Sabnzbd
- Jellystat
- Homepage
- Nginx Proxy Manager
- WordPress
- Portainer
- Other Docker Compose stacks

## Current Status

Project Phoenix is currently early development software.

The original production version is already protecting a real UGREEN NAS Docker folder, but this repository is being cleaned up into a reusable public project.

## Design Principles

- Lightweight first
- Bash based
- Raspberry Pi friendly
- No database required
- No web server required
- No telemetry
- No cloud account required
- Human-readable config, logs, and reports
- Optional extras can be added later

## Basic Architecture

```text
Docker host
   |
   | rsync over SSH
   v
Backup destination
