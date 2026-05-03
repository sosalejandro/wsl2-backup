# wsl2-backup configuration
# Copy this file to ~/.config/wsl2-backup/config.sh and edit as needed.
# This file is sourced by backup.sh — it's plain bash.

# ── rclone remotes ────────────────────────────────────────────────────────────
# Name of your Google Drive remote in rclone (rclone config → gdrive)
GDRIVE_REMOTE="gdrive"

# Name of your encrypted rclone remote for credentials (rclone config → gdrive-crypt)
# Set up as a crypt remote wrapping: ${GDRIVE_REMOTE}:Backups/WSL2/credentials
GDRIVE_CRYPT_REMOTE="gdrive-crypt"

# Root folder in Google Drive where backups land
GDRIVE_BACKUP_ROOT="Backups/WSL2"

# ── Distro label ──────────────────────────────────────────────────────────────
# Auto-detected from /etc/os-release by default (e.g. "ubuntu-24.04").
# Override here if you want a friendlier name.
# DISTRO_LABEL="my-ubuntu"

# ── Paths to back up ─────────────────────────────────────────────────────────
# Space-separated list of additional directories to sync (unencrypted).
# ~/Documents is always included. Add more here if needed.
EXTRA_PATHS=""
# EXTRA_PATHS="$HOME/work $HOME/scripts"

# ── rclone performance ────────────────────────────────────────────────────────
RCLONE_TRANSFERS=16
RCLONE_CHECKERS=32
RCLONE_CHUNK_SIZE="64M"   # smaller = faster retries on stalled uploads
RCLONE_BUFFER_SIZE="128M"
RCLONE_TIMEOUT="5m"       # abort stalled transfers after this long, then retry

# ── Logging ───────────────────────────────────────────────────────────────────
LOG_FILE="$HOME/.local/share/wsl2-backup/backup.log"
LOG_MAX_LINES=5000        # log is trimmed to this many lines after each run
