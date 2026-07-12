# Project Phoenix Agent Guidelines

These instructions apply to the entire repository.

## Architecture and dependencies

- Keep Project Phoenix Core lightweight and Bash-first.
- Prefer standard Unix tools.
- Do not add dependencies without explicit user approval.
- Put reusable logic in focused modules. Command modules should orchestrate those modules rather than contain reusable implementation details.

## Safety and repository hygiene

- Never read or display the contents of SSH private keys.
- Never stage, commit, push, or upload any of the following:
  - `config.conf`
  - `config.conf.backup.*`
  - keys or key files
  - logs
  - reports
  - history
  - discovery data
  - inventory data
  - manifests
  - status files
- Do not commit or push unless the user explicitly instructs you to do so.

## User experience

- Preserve beginner-friendly setup and recovery workflows.

## Validation and handoff

- Run tests inside WSL.
- After changes, run Bash syntax checks, ShellCheck, `git diff --check`, and `bash scripts/dev-test.sh`.
- Show the user the diff and the test results.
