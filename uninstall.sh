#!/usr/bin/env bash
# uninstall.sh — remove wsl2-backup from this distro
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✔${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC}  $*"; }

BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/wsl2-backup"
FILTER="$HOME/.config/rclone/wsl2-dev-filter.txt"
SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

echo "Uninstalling wsl2-backup..."
echo ""

# Stop and disable systemd timer if active
if command -v systemctl &>/dev/null && systemctl --user is-enabled wsl2-backup.timer &>/dev/null 2>&1; then
  systemctl --user disable --now wsl2-backup.timer
  ok "systemd timer disabled"
fi

# Remove systemd units
rm -f "$SYSTEMD_USER_DIR/wsl2-backup.service" "$SYSTEMD_USER_DIR/wsl2-backup.timer"
command -v systemctl &>/dev/null && systemctl --user daemon-reload 2>/dev/null || true
ok "systemd units removed"

# Remove binary
rm -f "$BIN_DIR/wsl2-backup"
ok "Backup script removed"

# Remove filter file
rm -f "$FILTER"
ok "Filter file removed"

# Config — ask before deleting
if [[ -d "$CONFIG_DIR" ]]; then
  read -r -p "Remove config at $CONFIG_DIR? [y/N] " ans
  if [[ "${ans,,}" == "y" ]]; then
    rm -rf "$CONFIG_DIR"
    ok "Config removed"
  else
    warn "Config kept at $CONFIG_DIR"
  fi
fi

echo ""
ok "Uninstall complete. rclone and its config were NOT removed."
warn "Your Google Drive backups are untouched."
