#!/usr/bin/env bash
set -euo pipefail
# Run as root from a systemd timer/cron after configuring paths below.
# A brief maintenance window makes SQLite and private files a coherent snapshot.
backup_root=/var/backups/study-ai
backup_dir="$backup_root/$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 700 -o study-ai -g study-ai "$backup_root" "$backup_dir"
systemctl stop study-ai
trap 'systemctl start study-ai' EXIT
cd /opt/study-ai/server
sudo -u study-ai env DATA_DIR=/var/lib/study-ai/data UPLOAD_DIR=/var/lib/study-ai/uploads /usr/bin/npm run backup -- "$backup_dir"
