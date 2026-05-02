#!/usr/bin/env bash
# install.sh — WSL2 Google Drive backup setup
# Usage (cloned):  bash install.sh
# Usage (one-line): curl -sL https://raw.githubusercontent.com/USER/REPO/main/install.sh | bash
set -euo pipefail

REPO_URL="https://github.com/sosalejandro/wsl2-backup"
RAW_URL="https://raw.githubusercontent.com/sosalejandro/wsl2-backup/main"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/wsl2-backup"
RCLONE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rclone"
SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
BIN_DIR="$HOME/.local/bin"

# ── Detect if running from a cloned repo or piped ────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-install.sh}")" 2>/dev/null && pwd || echo "")"
if [[ -f "$SCRIPT_DIR/backup.sh" && -f "$SCRIPT_DIR/filters/dev.txt" ]]; then
  REPO_DIR="$SCRIPT_DIR"
  FROM_REPO=true
else
  REPO_DIR=""
  FROM_REPO=false
fi

# ── Helpers ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✔${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC}  $*"; }
err()  { echo -e "${RED}✘${NC} $*"; exit 1; }
info() { echo -e "  $*"; }

fetch() {
  local url="$1" dest="$2"
  if command -v curl &>/dev/null; then
    curl -fsSL "$url" -o "$dest"
  elif command -v wget &>/dev/null; then
    wget -q "$url" -O "$dest"
  else
    err "Neither curl nor wget found. Install one and re-run."
  fi
}

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo "╔═══════════════════════════════════════╗"
echo "║     WSL2 → Google Drive Backup        ║"
echo "║           install.sh                  ║"
echo "╚═══════════════════════════════════════╝"
echo ""

# ── 1. Install rclone ─────────────────────────────────────────────────────────
if command -v rclone &>/dev/null; then
  ok "rclone already installed: $(rclone version --check 2>/dev/null | head -1 || rclone version | head -1)"
else
  info "Installing rclone..."
  curl https://rclone.org/install.sh | sudo bash
  ok "rclone installed"
fi

# ── 2. Create directories ────────────────────────────────────────────────────
mkdir -p "$CONFIG_DIR" "$RCLONE_CONFIG_DIR" "$BIN_DIR" "$SYSTEMD_USER_DIR"
mkdir -p "$HOME/.local/share/wsl2-backup"
ok "Directories ready"

# ── 3. Install filter file ────────────────────────────────────────────────────
FILTER_DEST="$RCLONE_CONFIG_DIR/wsl2-dev-filter.txt"
if [[ "$FROM_REPO" == true ]]; then
  cp "$REPO_DIR/filters/dev.txt" "$FILTER_DEST"
else
  fetch "${RAW_URL}/filters/dev.txt" "$FILTER_DEST"
fi
ok "Filter file installed: $FILTER_DEST"

# ── 4. Install backup script ──────────────────────────────────────────────────
BACKUP_BIN="$BIN_DIR/wsl2-backup"
if [[ "$FROM_REPO" == true ]]; then
  cp "$REPO_DIR/backup.sh" "$BACKUP_BIN"
else
  fetch "${RAW_URL}/backup.sh" "$BACKUP_BIN"
fi
chmod +x "$BACKUP_BIN"
ok "Backup script installed: $BACKUP_BIN"

# ── 5. Ensure ~/.local/bin is on PATH ────────────────────────────────────────
if ! echo "$PATH" | grep -q "$BIN_DIR"; then
  warn "~/.local/bin is not in your PATH."
  SHELL_RC=""
  [[ -f "$HOME/.zshrc" ]] && SHELL_RC="$HOME/.zshrc"
  [[ -f "$HOME/.bashrc" ]] && SHELL_RC="$HOME/.bashrc"
  if [[ -n "$SHELL_RC" ]]; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
    info "Added to $SHELL_RC — run: source $SHELL_RC"
  fi
fi

# ── 6. Create user config if not present ──────────────────────────────────────
USER_CONFIG="$CONFIG_DIR/config.sh"
if [[ -f "$USER_CONFIG" ]]; then
  ok "Config already exists: $USER_CONFIG"
else
  if [[ "$FROM_REPO" == true ]]; then
    cp "$REPO_DIR/config.example.sh" "$USER_CONFIG"
  else
    fetch "${RAW_URL}/config.example.sh" "$USER_CONFIG"
  fi
  ok "Config created: $USER_CONFIG"
  warn "Edit $USER_CONFIG to set your rclone remote names before running a backup."
fi

# ── 7. Set up systemd timer (if systemd is available) ─────────────────────────
SYSTEMD_AVAILABLE=false
if command -v systemctl &>/dev/null && systemctl --user status &>/dev/null 2>&1; then
  SYSTEMD_AVAILABLE=true
fi

if [[ "$SYSTEMD_AVAILABLE" == true ]]; then
  if [[ "$FROM_REPO" == true ]]; then
    cp "$REPO_DIR/systemd/wsl2-backup.service" "$SYSTEMD_USER_DIR/"
    cp "$REPO_DIR/systemd/wsl2-backup.timer"   "$SYSTEMD_USER_DIR/"
  else
    fetch "${RAW_URL}/systemd/wsl2-backup.service" "$SYSTEMD_USER_DIR/wsl2-backup.service"
    fetch "${RAW_URL}/systemd/wsl2-backup.timer"   "$SYSTEMD_USER_DIR/wsl2-backup.timer"
  fi

  systemctl --user daemon-reload
  systemctl --user enable --now wsl2-backup.timer
  ok "systemd timer enabled (daily backup at 02:00, persistent)"
  info "Check status: systemctl --user status wsl2-backup.timer"
  info "View logs:    journalctl --user -u wsl2-backup.service"
else
  warn "systemd not available in this distro."
  info "To enable it: add [boot] systemd=true to /etc/wsl.conf, then restart WSL2."
  echo ""
  info "For now, you can schedule via Windows Task Scheduler:"
  info "  Action:  wsl.exe"
  info "  Args:    -d $(. /etc/os-release && echo $PRETTY_NAME | tr ' ' '-') -e $BACKUP_BIN"
  info ""
  info "Or add to crontab (crontab -e):"
  info "  0 2 * * * $BACKUP_BIN >> \$HOME/.local/share/wsl2-backup/backup.log 2>&1"
fi

# ── 8. rclone remote check ────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────"
echo "  rclone remote setup"
echo "─────────────────────────────────────────"

RCLONE_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/rclone/rclone.conf"
GDRIVE_CONFIGURED=false
CRYPT_CONFIGURED=false

if [[ -f "$RCLONE_CONF" ]]; then
  grep -q '^\[gdrive\]'       "$RCLONE_CONF" 2>/dev/null && GDRIVE_CONFIGURED=true
  grep -q '^\[gdrive-crypt\]' "$RCLONE_CONF" 2>/dev/null && CRYPT_CONFIGURED=true
fi

if [[ "$GDRIVE_CONFIGURED" == true ]]; then
  ok "gdrive remote found in rclone.conf"
else
  warn "gdrive remote not configured."
  info "Run: rclone config"
  info "  → New remote → name: gdrive → type: drive"
  info "  → (try Y for browser auth — WSL2 often opens your Windows browser)"
  info "  → If that fails: run 'rclone authorize drive' in Windows PowerShell and paste the token"
fi

if [[ "$CRYPT_CONFIGURED" == true ]]; then
  ok "gdrive-crypt remote found in rclone.conf"
else
  warn "gdrive-crypt remote not configured."
  info "Run: rclone config"
  info "  → New remote → name: gdrive-crypt → type: crypt"
  info "  → Remote to encrypt: gdrive:Backups/WSL2/credentials"
  info "  → Encrypt filenames: standard"
  info "  → Set two strong passphrases and save them in your password manager"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────"
ok "Install complete."
echo ""
info "Next steps:"
info "  1. Configure rclone remotes if not done (see above)"
info "  2. Edit config: $USER_CONFIG"
info "  3. Dry run:  wsl2-backup --dry-run   (not yet: run backup.sh manually with --dry-run)"
info "  4. First backup: wsl2-backup"
echo ""
