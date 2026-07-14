<p align="center">
  <img src="assets/branding/phoenix-logo-v1.svg"
       alt="Project Phoenix Logo"
       width="220">
</p>

<h1 align="center">Project Phoenix</h1>

<p align="center">
  <strong>Rise. Recover. Restore.</strong>
</p>

![Version](https://img.shields.io/badge/version-v0.1.0--dev1-orange)
![Status](https://img.shields.io/badge/status-alpha-red)
![ShellCheck](https://img.shields.io/badge/ShellCheck-passing-brightgreen)
![Language](https://img.shields.io/badge/language-Bash-blue)
![Platform](https://img.shields.io/badge/platform-Linux-lightgrey)
![Transport](https://img.shields.io/badge/transport-SSH%20%2B%20rsync-purple)
![License](https://img.shields.io/badge/license-MIT-green)

**Project Phoenix** is a lightweight disaster recovery toolkit for self-hosted Docker environments.

It protects the parts of your Docker setup that matter most — configuration files, Compose projects, service folders, and recovery metadata — using standard Linux tools: **Bash, SSH, and rsync**.

Project Phoenix is built for homelab users, NAS owners, Raspberry Pi users, and self-hosters who want a simple way to recover their Docker configuration after disk failure, accidental deletion, or system rebuild.

---

## Why Project Phoenix?

Reinstalling Docker is easy.

Rebuilding years of carefully tuned services is not.

If you run self-hosted services such as Sonarr, Radarr, Sabnzbd, Homepage, Nginx Proxy Manager, Portainer, Jellystat, WordPress, or similar Docker Compose stacks, your configuration folders are often more valuable than the containers themselves.

Project Phoenix focuses on one goal:

> **Make recovery easier when something goes wrong.**

---

## What It Does

Project Phoenix helps you:

* Back up Docker configuration folders
* Send backups to another machine over SSH
* Use `rsync` for efficient file transfers
* Generate system and Docker discovery reports
* Run health checks before disaster strikes
* Keep recovery information human-readable
* Avoid heavy dependencies
* Keep your backup workflow simple and transparent

---

## What It Is Not

Project Phoenix is not:

* Enterprise backup software
* Cloud backup software
* A Docker management platform
* A database-backed backup system
* A replacement for tools like Borg, Restic, or Duplicati

It is intentionally smaller and simpler.

Its purpose is to help self-hosters recover Docker configuration quickly and confidently.

---

## Design Principles

Project Phoenix is built around three core principles.

### Lightweight

The core should run on small systems such as:

* Raspberry Pi
* NAS devices
* Mini PCs
* Low-power Linux servers

### Recovery First

A backup is only useful if it can be restored.

Every feature should improve recovery confidence.

### Transparent

No hidden databases.

No telemetry.

No cloud account.

No lock-in.

Plain Bash, plain text config, plain logs, and standard Linux tools.

---

## How It Works

```text
Docker host
    │
    │ rsync over SSH
    ▼
Backup destination
    │
    ▼
Recoverable Docker configuration
```

Example backup destinations:

* Raspberry Pi with USB storage
* Another NAS
* Linux server
* Remote SSH server
* Mini PC
* Dedicated backup machine

---

## Current Status

Project Phoenix is currently in early alpha development.

The project has:

* A modular Bash architecture
* ShellCheck-clean scripts
* A lightweight developer test runner
* Environment discovery
* Doctor diagnostics
* Requirements checking
* Restore guidance
* Documentation and security guidance

The original production version was created to protect a real UGREEN NAS Docker environment, but this repository is being shaped into a reusable public project.

---

## Requirements

Core requirements:

| Tool       | Purpose                            |
| ---------- | ---------------------------------- |
| Bash       | Runs Project Phoenix               |
| SSH client | Connects to backup destination     |
| rsync      | Performs efficient backup transfer |

Standard Linux utilities used:

* `find`
* `du`
* `df`
* `awk`
* `grep`
* `date`
* `mkdir`

Optional:

| Tool           | Purpose                                |
| -------------- | -------------------------------------- |
| Docker         | Enables Docker discovery and inventory |
| Docker Compose | Enables Compose-related discovery      |
| ShellCheck     | Developer quality checks               |

Docker is optional. Project Phoenix should still run basic checks and discovery without Docker installed.

---

## Quick Start

Clone the repository:

```bash
git clone https://github.com/Bonjam/ProjectPhoenix.git
cd ProjectPhoenix
```

Check requirements:

```bash
bash scripts/phoenix.sh requirements
```

Run the built-in test command:

```bash
bash scripts/phoenix.sh test
```

Run doctor:

```bash
bash scripts/phoenix.sh doctor
```

Run discovery:

```bash
bash scripts/phoenix.sh discovery
```

Create your configuration:

```bash
cp examples/config.example.conf config.conf
```

Edit it:

```bash
nano config.conf
```

Run a backup:

```bash
bash scripts/phoenix.sh backup
```

---

## Example Configuration

Copy the example file:

```bash
cp examples/config.example.conf config.conf
```

Example values:

Project Phoenix gives each backup destination a stable local-state namespace.
The three profile fields are optional: existing configurations that omit them
continue to use `default`, `Default Destination`, and `ssh-rsync`.

```bash
SOURCE="/srv/docker/"
DESTINATION="/mnt/backups/docker-backup/"
BACKUP_HOST="backup-server.local"
BACKUP_USER="backup-user"
SSH_KEY="/opt/project-phoenix/ssh/id_ed25519"
EXCLUDE_FILE="/opt/project-phoenix/exclude.txt"
DESTINATION_ID="pi-usb"
DESTINATION_NAME="Raspberry Pi USB"
DESTINATION_TRANSPORT="ssh-rsync"
```

Destination IDs may contain only lowercase letters, digits, and hyphens and
must begin with a letter or digit. Project Phoenix supports `ssh-rsync` and
`local`. SMB, Google Drive, and rclone remain planned and are not implemented.

Your real `config.conf` should never be committed to Git.

### Windows local storage

The `local` transport is intended for storage mounted directly in the current
Linux or WSL environment. WSL normally exposes Windows drives beneath
`/mnt/<drive-letter>/`; use a dedicated backup directory such as
`/mnt/c/ProjectPhoenixBackups/nas-docker-backup/` and quote paths containing
spaces. The source and destination must never overlap.

```bash
DESTINATION_ID="windows-local"
DESTINATION_NAME="Windows Local Backup"
DESTINATION_TRANSPORT="local"
DESTINATION_PATH="/mnt/c/ProjectPhoenixBackups/nas-docker-backup/"
LOCAL_ALLOWED_ROOTS="/mnt/c:/mnt/d:/mnt/e:/mnt/f:/tmp"
```

Local profiles do not use `BACKUP_HOST`, `BACKUP_USER`, or `SSH_KEY`.
`DESTINATION_PATH` is preferred; `DESTINATION` remains a compatibility alias.
The local copied integrity-reference directory still contains the name
`remote` for layout compatibility, but it represents the selected destination
for every transport.

Windows-local storage protects against failure of the NAS disk, but it may not
protect against failure of the Windows PC or its disk. Maintain another
independent copy for broader resilience.

### Legacy state migration

`destination-migration` safely analyses existing local `history/`, copied
remote-integrity references, `status/`, and `reports/` without changing them.
After defining an explicit non-default destination profile, run
`destination-migrate` to copy eligible files into that destination's local
namespace. It stages, compares, and verifies each copy, leaves the legacy
state intact for rollback, and never changes remote backup data.

The confirmed command displays its analysis before asking for the exact phrase
`MIGRATE LEGACY STATE TO <destination-id>`. A different response cancels the
migration. Conflicts are never overwritten, and `config.conf` is never changed
automatically.

---

## Commands

| Command        | Description                            |
| -------------- | -------------------------------------- |
| `help`         | Show available commands                |
| `banner`       | Show Project Phoenix banner            |
| `info`         | Show project and core information      |
| `requirements` | Check required system tools            |
| `test`         | Run lightweight internal tests         |
| `destination-info` | Show the active destination profile without connecting |
| `local-check` | Inspect a local destination read-only without creating it |
| `destination-migration` | Analyse legacy local state without changing it |
| `destination-migrate` | Confirm a copy-first local legacy-state migration |
| `doctor`       | Run health diagnostics                 |
| `discovery`    | Discover system and Docker environment |
| `check-config` | Validate configuration                 |
| `status`       | Show current backup status             |
| `inventory`    | Generate source inventory              |
| `backup`       | Run backup                             |
| `restore`      | Show restore assistant                 |
| `report`       | Generate text report                   |
| `html-report`  | Generate static HTML report            |
| `confidence`   | Show recovery confidence score         |
| `test-logging` | Test logging output                    |

Example:

```bash
bash scripts/phoenix.sh doctor
```

---

## Developer Test Runner

Project Phoenix includes a lightweight developer QA script:

```bash
bash scripts/dev-test.sh
```

It currently checks:

* ShellCheck
* Help command
* Banner command
* Info command
* Requirements command
* Test command
* Doctor command
* Discovery command

Expected result:

```text
PROJECT PHOENIX DEV TEST: PASS
```

---

## Project Structure

```text
ProjectPhoenix/
│
├── assets/
│   ├── ascii/
│   ├── branding/
│   └── logo/
│
├── docs/
│   ├── INSTALL.md
│   ├── RELEASE.md
│   └── ROADMAP.md
│
├── examples/
│   └── config.example.conf
│
├── lib/
│   ├── backup.sh
│   ├── banner.sh
│   ├── config.sh
│   ├── core.sh
│   ├── discovery.sh
│   ├── doctor.sh
│   ├── logging.sh
│   ├── module-loader.sh
│   └── ...
│
├── restore/
├── screenshots/
├── scripts/
│   ├── phoenix.sh
│   └── dev-test.sh
│
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
├── PHILOSOPHY.md
├── README.md
├── SECURITY.md
└── VERSION
```

---

## Security

Project Phoenix is designed to keep public source code separate from private production configuration.

Never commit:

```text
config.conf
ssh/
id_ed25519
id_ed25519.pub
*.pem
*.key
logs/
status/
history/
reports/
inventory/
discovery/
manifests/
```

These files may contain private paths, hostnames, IP addresses, logs, system inventory, or SSH keys.

See:

```text
SECURITY.md
```

---

## Documentation

| Document          | Purpose            |
| ----------------- | ------------------ |
| `docs/INSTALL.md` | Installation guide |
| `docs/ROADMAP.md` | Project roadmap    |
| `docs/RELEASE.md` | Release checklist  |
| `SECURITY.md`     | Security guidance  |
| `CONTRIBUTING.md` | Contribution guide |
| `PHILOSOPHY.md`   | Project principles |

---

## Roadmap

Current development focus:

* Polish the CLI
* Improve first-run experience
* Add a setup wizard
* Improve recovery confidence checks
* Strengthen restore workflow
* Prepare first public release

Future ideas:

* Docker container version
* Optional web dashboard
* Multiple backup destinations
* Restore simulation
* Notification support
* Community plugins

See:

```text
docs/ROADMAP.md
```

---

## Philosophy

Project Phoenix should remain:

* Lightweight
* Bash-first
* Linux-native
* Human-readable
* Recovery-focused
* Privacy-respecting
* Simple enough to understand

Every feature should answer one question:

> **Does this make recovery easier?**

If not, it probably does not belong in the core.

See:

```text
PHILOSOPHY.md
```

---

## Contributing

Contributions, testing, documentation improvements, and feedback are welcome.

Useful contributions include:

* Testing on Raspberry Pi
* Testing on NAS devices
* Testing with different Docker layouts
* Improving documentation
* Improving error messages
* Testing restore workflows
* Suggesting safer defaults

See:

```text
CONTRIBUTING.md
```

---

## License

Project Phoenix is released under the MIT License.

See:

```text
LICENSE
```

---

## Final Note

Project Phoenix was created from a simple need:

> Protect Docker configuration so recovery is faster, easier, and less stressful.

Containers can be recreated.

Carefully tuned configurations are harder to replace.

Project Phoenix exists to help those configurations rise again.
