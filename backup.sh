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
RCLONE_TRANSFERS="${RCLONE_TRANSFERS:-16}"
RCLONE_CHECKERS="${RCLONE_CHECKERS:-32}"
RCLONE_CHUNK_SIZE="${RCLONE_CHUNK_SIZE:-64M}"
RCLONE_BUFFER_SIZE="${RCLONE_BUFFER_SIZE:-128M}"
RCLONE_TIMEOUT="${RCLONE_TIMEOUT:-5m}"
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
START_TIME=$(date +%s)

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

elapsed() {
  local secs=$(( $(date +%s) - START_TIME ))
  printf '%dm%ds' $(( secs / 60 )) $(( secs % 60 ))
}

# Full-featured sync — for large directories (Documents, extra paths)
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
    --order-by size,desc \
    --multi-thread-streams=4 \
    --multi-thread-cutoff=100M \
    --drive-pacer-min-sleep=10ms \
    --drive-pacer-burst=200 \
    --retries=10 \
    --retries-sleep=30s \
    --low-level-retries=20 \
    --timeout="$RCLONE_TIMEOUT" \
    --contimeout=60s \
    --log-file="$LOG_FILE" \
    --log-level=INFO \
    --stats=10s \
    --stats-one-line \
    "$@"
}

# Lightweight sync — for small directories (credentials, config, dotfiles)
# Skips --fast-list and --order-by overhead which aren't worth it for <100 files
rclone_sync_small() {
  local src="$1" dst="$2"
  shift 2
  rclone sync "$src" "$dst" \
    --transfers="$RCLONE_TRANSFERS" \
    --checkers="$RCLONE_CHECKERS" \
    --drive-chunk-size="$RCLONE_CHUNK_SIZE" \
    --drive-upload-cutoff="$RCLONE_CHUNK_SIZE" \
    --buffer-size="$RCLONE_BUFFER_SIZE" \
    --drive-pacer-min-sleep=10ms \
    --drive-pacer-burst=200 \
    --retries=10 \
    --retries-sleep=30s \
    --low-level-retries=20 \
    --timeout="$RCLONE_TIMEOUT" \
    --contimeout=60s \
    --log-file="$LOG_FILE" \
    --log-level=INFO \
    --stats=10s \
    --stats-one-line \
    "$@"
}

check_rclone_remote() {
  local remote="$1"
  local output
  output=$(rclone lsd "${remote}:" 2>&1) || {
    # "directory not found" means remote is reachable but path doesn't exist yet — OK,
    # rclone sync will create it on first run
    if echo "$output" | grep -q "directory not found"; then
      return 0
    fi
    log "ERROR: rclone remote '${remote}' not found or unreachable."
    log "Run: rclone config — to set it up."
    exit 1
  }
}

# Wait for all background PIDs, log warnings on failure (don't abort)
wait_jobs() {
  local label="$1"
  shift
  local failed=0
  for pid in "$@"; do
    if ! wait "$pid"; then
      log "WARN: a $label background sync failed (pid $pid) — check log above"
      failed=1
    fi
  done
  (( failed )) && log "WARN: $label phase completed with errors" || true
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
dpkg --get-selections           > "$META_DIR/packages.txt"          2>/dev/null || true
go env                          > "$META_DIR/go-env.txt"             2>/dev/null || true
ls "$(go env GOPATH)/bin"       > "$META_DIR/go-tools.txt"          2>/dev/null || true
node --version                  > "$META_DIR/node-version.txt"      2>/dev/null || true
dotnet --list-sdks              > "$META_DIR/dotnet-sdks.txt"       2>/dev/null || true
dotnet tool list -g             > "$META_DIR/dotnet-tools.txt"      2>/dev/null || true
az --version                    > "$META_DIR/azure-cli-version.txt" 2>/dev/null || true
aws --version                   > "$META_DIR/aws-cli-version.txt"   2>/dev/null || true
uname -r                        > "$META_DIR/kernel.txt"            2>/dev/null || true

# ── Documents (largest sync — sequential, uploads biggest files first) ────────
log "Syncing ~/Documents..."
rclone_sync "$HOME/Documents" "$GDRIVE_DISTRO/Documents" \
  --filter-from "$FILTER_FILE"
log "Documents done ($(elapsed) elapsed)"

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

# ── Small plaintext syncs — run in parallel ───────────────────────────────────
log "Syncing metadata, dotfiles, config, local-bin (parallel)..."
SMALL_PIDS=()

# Metadata
rclone_sync_small "$META_DIR" "$GDRIVE_DISTRO/meta" &
SMALL_PIDS+=($!)

# Dotfiles — all files in one rclone call instead of N separate calls
DOTFILES=(
  .bashrc .bash_profile .bash_aliases .bash_history
  .zshrc .zsh_history .zprofile
  .profile .aliases .inputrc
  .gitconfig .gitignore_global
  .npmrc .yarnrc .yarnrc.yml
  .tmux.conf .screenrc .editorconfig
  .psqlrc .sqliterc .myclirc
)
DOTFILE_INCLUDES=()
for f in "${DOTFILES[@]}"; do
  [[ -f "$HOME/$f" ]] && DOTFILE_INCLUDES+=("--include=$f")
done
if [[ ${#DOTFILE_INCLUDES[@]} -gt 0 ]]; then
  rclone copy "$HOME" "$GDRIVE_DISTRO/dotfiles" \
    "${DOTFILE_INCLUDES[@]}" \
    --transfers="$RCLONE_TRANSFERS" \
    --drive-pacer-min-sleep=10ms \
    --drive-pacer-burst=200 \
    --retries=10 \
    --retries-sleep=30s \
    --timeout="$RCLONE_TIMEOUT" \
    --log-file="$LOG_FILE" \
    --log-level=INFO &
  SMALL_PIDS+=($!)
fi

# ~/.config (curated, minus caches and secret key material)
rclone_sync_small "$HOME/.config" "$GDRIVE_DISTRO/config" \
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
  --exclude "age/**" &
SMALL_PIDS+=($!)

# ~/.local/bin (custom scripts)
if [[ -d "$HOME/.local/bin" ]]; then
  rclone_sync_small "$HOME/.local/bin" "$GDRIVE_DISTRO/local-bin" &
  SMALL_PIDS+=($!)
fi

wait_jobs "plaintext" "${SMALL_PIDS[@]}"
log "Small syncs done ($(elapsed) elapsed)"

# ── Encrypted syncs — all run in parallel ─────────────────────────────────────
log "Syncing credentials and keys (encrypted, parallel)..."
CRYPT_PIDS=()

# GPG keys
if [[ -d "$HOME/.gnupg" ]]; then
  rclone_sync_small "$HOME/.gnupg" "${GDRIVE_CRYPT_REMOTE}:gnupg" &
  CRYPT_PIDS+=($!)
fi

# Credential directories
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
    rclone_sync_small "$path" "${GDRIVE_CRYPT_REMOTE}:${label}" &
    CRYPT_PIDS+=($!)
  fi
done

# Docker registry auth (single file)
if [[ -f "$HOME/.docker/config.json" ]]; then
  log "  └─ ~/.docker/config.json"
  rclone copy "$HOME/.docker/config.json" "${GDRIVE_CRYPT_REMOTE}:docker/" \
    --retries=10 \
    --timeout="$RCLONE_TIMEOUT" \
    --log-file="$LOG_FILE" \
    --log-level=INFO &
  CRYPT_PIDS+=($!)
fi

wait_jobs "encrypted" "${CRYPT_PIDS[@]}"
log "Encrypted syncs done ($(elapsed) elapsed)"

# ── Wrap up ───────────────────────────────────────────────────────────────────
log_trim
log "Backup complete in $(elapsed)."
log "──────────────────────────────────────────────"
