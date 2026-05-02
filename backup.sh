#!/usr/bin/env bash
# backup.sh — WSL2 → Google Drive backup via rclone
# Reads config from ~/.config/wsl2-backup/config.sh
set -euo pipefail

# ── Load config ───────────────────────────────────────────────────────────────
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/wsl2-backup/config.sh"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: Config not found at $CONFIG_FILE"
  echo "Run install.sh first, or copy config.example.sh to $CONFIG_FILE"
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

# ── Defaults (can be overridden in config.sh) ─────────────────────────────────
GDRIVE_REMOTE="${GDRIVE_REMOTE:-gdrive}"
GDRIVE_CRYPT_REMOTE="${GDRIVE_CRYPT_REMOTE:-gdrive-crypt}"
GDRIVE_BACKUP_ROOT="${GDRIVE_BACKUP_ROOT:-Backups/WSL2}"
RCLONE_TRANSFERS="${RCLONE_TRANSFERS:-8}"
RCLONE_CHECKERS="${RCLONE_CHECKERS:-16}"
RCLONE_CHUNK_SIZE="${RCLONE_CHUNK_SIZE:-256M}"
RCLONE_BUFFER_SIZE="${RCLONE_BUFFER_SIZE:-256M}"
LOG_FILE="${LOG_FILE:-$HOME/.local/share/wsl2-backup/backup.log}"
LOG_MAX_LINES="${LOG_MAX_LINES:-5000}"
EXTRA_PATHS="${EXTRA_PATHS:-}"

# ── Distro label ──────────────────────────────────────────────────────────────
if [[ -n "${DISTRO_LABEL:-}" ]]; then
  DISTRO="$DISTRO_LABEL"
elif [[ -f /etc/os-release ]]; then
  # shellcheck source=/dev/null
  DISTRO=$(. /etc/os-release && echo "${ID}-${VERSION_ID}" | tr ' ' '-')
else
  DISTRO="unknown"
fi

GDRIVE_DISTRO="${GDRIVE_REMOTE}:${GDRIVE_BACKUP_ROOT}/${DISTRO}"
FILTER_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/rclone/wsl2-dev-filter.txt"

# ── Helpers ───────────────────────────────────────────────────────────────────
mkdir -p "$(dirname "$LOG_FILE")"

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg" | tee -a "$LOG_FILE"
}

log_trim() {
  if [[ -f "$LOG_FILE" ]]; then
    local lines
    lines=$(wc -l < "$LOG_FILE")
    if (( lines > LOG_MAX_LINES )); then
      tail -n "$LOG_MAX_LINES" "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
  fi
}

rclone_sync() {
  local src="$1" dst="$2"
  shift 2
  rclone sync "$src" "$dst" \
    --transfers="$RCLONE_TRANSFERS" \
    --checkers="$RCLONE_CHECKERS" \
    --drive-chunk-size="$RCLONE_CHUNK_SIZE" \
    --drive-upload-cutoff="$RCLONE_CHUNK_SIZE" \
    --buffer-size="$RCLONE_BUFFER_SIZE" \
    --fast-list \
    --log-file="$LOG_FILE" \
    --log-level=INFO \
    "$@"
}

rclone_copy_file() {
  local src="$1" dst="$2"
  rclone copy "$src" "$dst" \
    --log-file="$LOG_FILE" \
    --log-level=INFO
}

check_rclone_remote() {
  local remote="$1"
  if ! rclone lsd "${remote}:" &>/dev/null; then
    log "ERROR: rclone remote '${remote}' not found or unreachable."
    log "Run: rclone config — to set it up."
    exit 1
  fi
}

# ── Preflight ─────────────────────────────────────────────────────────────────
if ! command -v rclone &>/dev/null; then
  log "ERROR: rclone not installed. Run install.sh first."
  exit 1
fi

if [[ ! -f "$FILTER_FILE" ]]; then
  log "ERROR: Filter file not found at $FILTER_FILE"
  log "Run install.sh to install it."
  exit 1
fi

log "──────────────────────────────────────────────"
log "Starting backup — distro: $DISTRO"
log "Destination: $GDRIVE_DISTRO"
log "──────────────────────────────────────────────"

check_rclone_remote "$GDRIVE_REMOTE"
check_rclone_remote "$GDRIVE_CRYPT_REMOTE"

# ── Pre-backup metadata ───────────────────────────────────────────────────────
META_DIR="$HOME/.local/share/wsl2-backup/meta"
mkdir -p "$META_DIR"

log "Capturing environment metadata..."
dpkg --get-selections           > "$META_DIR/packages.txt"        2>/dev/null || true
go env                          > "$META_DIR/go-env.txt"           2>/dev/null || true
ls "$(go env GOPATH)/bin"       > "$META_DIR/go-tools.txt"        2>/dev/null || true
node --version                  > "$META_DIR/node-version.txt"    2>/dev/null || true
dotnet --list-sdks              > "$META_DIR/dotnet-sdks.txt"     2>/dev/null || true
dotnet tool list -g             > "$META_DIR/dotnet-tools.txt"    2>/dev/null || true
az --version                    > "$META_DIR/azure-cli-version.txt" 2>/dev/null || true
aws --version                   > "$META_DIR/aws-cli-version.txt" 2>/dev/null || true
uname -r                        > "$META_DIR/kernel.txt"          2>/dev/null || true

# ── Documents ─────────────────────────────────────────────────────────────────
log "Syncing ~/Documents..."
rclone_sync "$HOME/Documents" "$GDRIVE_DISTRO/Documents" \
  --filter-from "$FILTER_FILE"

# ── Extra paths ───────────────────────────────────────────────────────────────
if [[ -n "$EXTRA_PATHS" ]]; then
  for extra in $EXTRA_PATHS; do
    if [[ -d "$extra" ]]; then
      label=$(basename "$extra")
      log "Syncing extra path: $extra..."
      rclone_sync "$extra" "$GDRIVE_DISTRO/extra/$label" \
        --filter-from "$FILTER_FILE"
    else
      log "WARN: Extra path not found, skipping: $extra"
    fi
  done
fi

# ── Metadata ──────────────────────────────────────────────────────────────────
log "Syncing environment metadata..."
rclone_sync "$META_DIR" "$GDRIVE_DISTRO/meta"

# ── Dotfiles (individual files) ───────────────────────────────────────────────
log "Syncing dotfiles..."
DOTFILES_DEST="$GDRIVE_DISTRO/dotfiles"
DOTFILES=(
  .bashrc .bash_profile .bash_aliases .bash_history
  .zshrc .zsh_history .zprofile
  .profile .aliases .inputrc
  .gitconfig .gitignore_global
  .npmrc .yarnrc .yarnrc.yml
  .tmux.conf .screenrc .editorconfig
  .psqlrc .sqliterc .myclirc
)
for f in "${DOTFILES[@]}"; do
  [[ -f "$HOME/$f" ]] && rclone_copy_file "$HOME/$f" "$DOTFILES_DEST/"
done

# ── ~/.config (curated, minus caches and secret key material) ────────────────
log "Syncing ~/.config..."
rclone_sync "$HOME/.config" "$GDRIVE_DISTRO/config" \
  --exclude "google-chrome/**" \
  --exclude "chromium/**" \
  --exclude "Code/**" \
  --exclude "*/Cache/**" \
  --exclude "*/cache/**" \
  --exclude "*/CachedData/**" \
  --exclude "nvim/plugged/**" \
  --exclude "nvim/lazy/**" \
  --exclude "nvim/mason/**" \
  --exclude "sops/**" \
  --exclude "age/**"

# ── ~/.local/bin (custom scripts) ────────────────────────────────────────────
if [[ -d "$HOME/.local/bin" ]]; then
  log "Syncing ~/.local/bin..."
  rclone_sync "$HOME/.local/bin" "$GDRIVE_DISTRO/local-bin"
fi

# ── ~/.gnupg (GPG keys — encrypted remote) ───────────────────────────────────
if [[ -d "$HOME/.gnupg" ]]; then
  log "Syncing ~/.gnupg (encrypted)..."
  rclone_sync "$HOME/.gnupg" "${GDRIVE_CRYPT_REMOTE}:gnupg"
fi

# ── Credentials (encrypted remote) ───────────────────────────────────────────
log "Syncing credentials (encrypted)..."
declare -A CRED_PATHS=(
  [ssh]="$HOME/.ssh"
  [aws]="$HOME/.aws"
  [azure]="$HOME/.azure"
  [kube]="$HOME/.kube"
  [gh]="$HOME/.config/gh"
  [terraform]="$HOME/.terraform.d"
  [age]="$HOME/.age"
  [sops]="$HOME/.config/sops"
)

for label in "${!CRED_PATHS[@]}"; do
  path="${CRED_PATHS[$label]}"
  if [[ -d "$path" ]]; then
    log "  └─ $path"
    rclone_sync "$path" "${GDRIVE_CRYPT_REMOTE}:${label}"
  fi
done

# Docker registry auth only (not the full ~/.docker which holds image layers)
if [[ -f "$HOME/.docker/config.json" ]]; then
  log "  └─ ~/.docker/config.json"
  rclone_copy_file "$HOME/.docker/config.json" "${GDRIVE_CRYPT_REMOTE}:docker/"
fi

# ── Wrap up ───────────────────────────────────────────────────────────────────
log_trim
log "Backup complete."
log "──────────────────────────────────────────────"
