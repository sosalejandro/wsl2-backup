# wsl2-backup

Backs up WSL2 dev environments to Google Drive using rclone. Syncs code, dotfiles,
tool configs, and credentials (encrypted). Works across multiple distros.

## What gets backed up

| What | Destination | Encrypted |
|---|---|---|
| `~/Documents` (code projects) | `gdrive:Backups/WSL2/<distro>/Documents` | No |
| dotfiles (`.bashrc`, `.gitconfig`, etc.) | `gdrive:Backups/WSL2/<distro>/dotfiles` | No |
| `~/.config` (minus caches) | `gdrive:Backups/WSL2/<distro>/config` | No |
| `~/.local/bin` (custom scripts) | `gdrive:Backups/WSL2/<distro>/local-bin` | No |
| Environment metadata (packages, go env, dotnet tools) | `gdrive:Backups/WSL2/<distro>/meta` | No |
| `~/.ssh`, `~/.aws`, `~/.azure`, `~/.kube`, `~/.gnupg` | `gdrive-crypt:` | **Yes** |
| `~/.config/gh`, `~/.terraform.d` | `gdrive-crypt:` | **Yes** |
| `~/.docker/config.json` | `gdrive-crypt:docker/` | **Yes** |

Build artifacts, caches, and `node_modules` are excluded via `filters/dev.txt`.

## Install

### Option A — clone the repo
```bash
git clone https://github.com/sosalejandro/wsl2-backup
cd wsl2-backup
bash install.sh
```

### Option B — one-liner (no git required)
```bash
curl -sL https://raw.githubusercontent.com/sosalejandro/wsl2-backup/main/install.sh | bash
```

The installer:
- Installs rclone if not present
- Places `wsl2-backup` in `~/.local/bin`
- Copies the filter file to `~/.config/rclone/wsl2-dev-filter.txt`
- Creates `~/.config/wsl2-backup/config.sh` from the example template
- Enables a systemd timer (daily at 02:00) if systemd is available

## Setup (one-time, per distro)

### 1. Configure rclone Google Drive remote

```bash
rclone config
# New remote → name: gdrive → type: drive
# Try Y for browser auth (WSL2 often opens your Windows browser)
```

If the browser doesn't open, run on Windows:
```powershell
winget install Rclone.Rclone
rclone authorize "drive"
# paste the printed token back into the WSL2 config prompt
```

### 2. Configure encrypted remote for credentials

```bash
rclone config
# New remote → name: gdrive-crypt → type: crypt
# Remote to encrypt: gdrive:Backups/WSL2/credentials
# Encrypt filenames: standard
# Set two passphrases → save them in your password manager
```

### 3. Edit your config

```bash
nano ~/.config/wsl2-backup/config.sh
```

At minimum confirm `GDRIVE_REMOTE` and `GDRIVE_CRYPT_REMOTE` match your rclone remote names.

### 4. First backup (dry run first)

```bash
# See what would be uploaded without actually uploading
rclone sync ~/Documents gdrive:Backups/WSL2/test/Documents \
  --filter-from ~/.config/rclone/wsl2-dev-filter.txt \
  --dry-run

# Run the real backup
wsl2-backup
```

## Usage

```bash
wsl2-backup          # run a backup now
wsl2-backup --help   # not implemented — just read the script
```

Logs: `~/.local/share/wsl2-backup/backup.log`

## Multiple distros

Run `bash install.sh` inside each WSL2 distro. Each distro backs up to its own
subfolder (`gdrive:Backups/WSL2/ubuntu-24.04/`, etc.).

Credentials are shared — if `~/.aws` is the same across distros, you only need
to back it up from your primary distro.

From Windows, you can trigger all distros via Task Scheduler with a PowerShell
loop over `wsl.exe -d <distro> -e wsl2-backup`.

## Automation

**systemd (Ubuntu 22.04+ with systemd enabled):**
```bash
# Check status
systemctl --user status wsl2-backup.timer

# View logs
journalctl --user -u wsl2-backup.service -f
```

**Enable systemd in WSL2** if not already on:
```ini
# /etc/wsl.conf
[boot]
systemd=true
```
Then `wsl --shutdown` from PowerShell and reopen.

**cron (fallback):**
```bash
crontab -e
# add:
0 2 * * * $HOME/.local/bin/wsl2-backup >> $HOME/.local/share/wsl2-backup/backup.log 2>&1
```

## Uninstall

```bash
bash uninstall.sh
```

Removes the script, filter file, systemd units, and optionally the config.
rclone and your Google Drive backups are untouched.
