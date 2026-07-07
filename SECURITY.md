# Security

Project Phoenix is designed to separate public source code from private production configuration.

## Never Commit Secrets

Do not commit:

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