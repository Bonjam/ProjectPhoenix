# Roadmap

Project Phoenix is being developed as a lightweight disaster recovery toolkit for self-hosted Docker environments.

## v0.1.0 — First Public Preview

Goal: make the project understandable, safe, and usable.

- GitHub-ready README
- Example configuration
- Install guide
- Security guide
- Lightweight Bash CLI
- rsync over SSH backup engine
- Restore assistant
- Doctor diagnostics
- Environment discovery
- Static reports

## v0.2.0 — Usability

- Installer script
- `phoenix` command shortcut
- Better first-run setup
- Cleaner terminal output
- Improved error messages
- Example exclude file
- Basic screenshots

## v0.3.0 — Recovery Confidence

- Improved recovery confidence score
- Backup freshness checks
- Destination space checks
- Restore kit validation
- Compose file protection checks

## v1.0.0 — Stable Core

- Stable backup engine
- Stable restore workflow
- Clear documentation
- Tested install process
- Lightweight release package

## Phase 2 — Multi-Destination Resilience

The destination-profile foundation introduces stable destination IDs and
isolated local history, status, reports, and copied integrity references while
preserving existing single-destination configurations as the `default`
profile. The only supported transport in this milestone remains `ssh-rsync`.
Windows/local, SMB, Google Drive, and rclone providers are planned follow-up
work and are not implemented yet.

The first migration workflow supports a read-only legacy-state analysis and an
explicitly confirmed, copy-first migration into one validated destination
namespace. It retains legacy local state for rollback, requires the exact
`MIGRATE LEGACY STATE TO <destination-id>` phrase, and does not change remote
backup data. Destructive legacy cleanup is not part of this milestone.

## Future Ideas

- Docker container version
- Optional web dashboard
- Notifications
- Multiple backup destinations
- Restore simulation
- Community plugins
