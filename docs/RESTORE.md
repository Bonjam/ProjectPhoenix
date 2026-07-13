# Project Phoenix Restore Guide

This metadata was published with the backup so recovery instructions remain
available on a fresh system.

1. Install Project Phoenix and copy a validated config.conf into the project.
2. Run `bash scripts/phoenix.sh recover` to inspect the backup read-only.
3. Run `bash scripts/phoenix.sh restore-dry-run` to preview restored files.
4. Review the preview, then use `restore-confirm` only when ready.
5. Run `bash scripts/phoenix.sh verify-restore` before starting containers.

Project Phoenix does not start Docker during recovery verification.
