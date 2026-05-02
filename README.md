# wsl2-backup

Backs up WSL2 dev environments to Google Drive using rclone. Syncs code, dotfiles,
tool configs, and credentials (encrypted). Works across multiple distros with a
single one-liner install.

Built for Go, Node/TypeScript, C#/.NET, AWS, and Azure dev environments.

---

## Table of Contents

- [What gets backed up](#what-gets-backed-up)
- [Prerequisites](#prerequisites)
- [Step 1 — Install](#step-1--install)
- [Step 2 — Configure the gdrive remote](#step-2--configure-the-gdrive-remote-google-drive)
- [Step 3 — Configure the gdrive-crypt remote](#step-3--configure-the-gdrive-crypt-remote-encrypted-credentials)
- [Step 4 — Protect the rclone config](#step-4--protect-the-rclone-config)
- [Step 5 — Edit your backup config](#step-5--edit-your-backup-config)
- [Step 6 — Dry run](#step-6--dry-run-before-the-first-real-backup)
- [Step 7 — First backup](#step-7--run-the-first-backup)
- [Step 8 — Verify the schedule](#step-8--verify-the-automated-schedule)
- [Multiple distros](#multiple-distros)
- [File locations reference](#file-locations-reference)
- [Uninstall](#uninstall)

---

## What gets backed up

| What | Destination | Encrypted |
|---|---|---|
| `~/Documents` (code projects) | `gdrive:Backups/WSL2/<distro>/Documents` | No |
| Dotfiles (`.bashrc`, `.gitconfig`, `.npmrc`, etc.) | `gdrive:Backups/WSL2/<distro>/dotfiles` | No |
| `~/.config` (minus caches) | `gdrive:Backups/WSL2/<distro>/config` | No |
| `~/.local/bin` (custom scripts) | `gdrive:Backups/WSL2/<distro>/local-bin` | No |
| Environment metadata (packages, go env, dotnet tools) | `gdrive:Backups/WSL2/<distro>/meta` | No |
| `~/.ssh`, `~/.aws`, `~/.azure`, `~/.kube`, `~/.gnupg` | `gdrive-crypt:` | **Yes** |
| `~/.config/gh`, `~/.terraform.d` | `gdrive-crypt:` | **Yes** |
| `~/.docker/config.json` | `gdrive-crypt:docker/` | **Yes** |

Build artifacts, caches, and `node_modules` are excluded via [`filters/dev.txt`](filters/dev.txt).

---

## Prerequisites

- WSL2 running a Debian-based distro (Ubuntu 22.04 / 24.04 recommended)
- A Google account with Google Drive storage available
- Internet access from within WSL2
- `curl` (pre-installed on Ubuntu)

---

## Step 1 — Install

Run this inside the WSL2 distro you want to back up.

**Option A — one-liner (no git required):**

```bash
curl -sL https://raw.githubusercontent.com/sosalejandro/wsl2-backup/main/install.sh | bash
```

**Option B — clone and inspect first:**

```bash
git clone https://github.com/sosalejandro/wsl2-backup
cd wsl2-backup
bash install.sh
```

The installer will:

- Install rclone if not already present
- Place the `wsl2-backup` command in `~/.local/bin`
- Copy `filters/dev.txt` to `~/.config/rclone/wsl2-dev-filter.txt`
- Create `~/.config/wsl2-backup/config.sh` from the template
- Enable a systemd daily timer at 02:00 if systemd is available, or print cron/Task Scheduler instructions

At the end it reports which rclone remotes are still missing. That is expected — configure them in the next two steps.

---

## Step 2 — Configure the `gdrive` remote (Google Drive)

```bash
rclone config
```

Answer the prompts as follows:

```
No remotes found, make a new one? → n
name> gdrive
Storage> drive
client_id>              (leave blank, press Enter)
client_secret>          (leave blank, press Enter)
scope> 1                (full access)
root_folder_id>         (leave blank)
service_account_file>   (leave blank)
Edit advanced config? → n
```

When asked about browser authentication:

```
Use web browser to automatically authenticate rclone with remote?
y/n> y
```

**Try `y` first.** WSL2 on Windows 10/11 usually opens your Windows browser
automatically via the WSL bridge. Log in with your Google account, grant access,
and you are done.

```
Configure this as a Shared Drive (Team Drive)? → n
Keep this "gdrive" remote? → y
```

**Verify:**

```bash
rclone lsd gdrive:
rclone about gdrive:
```

You should see your Drive folders and storage usage printed.

---

### Fallback: authenticate via Windows (if no browser opened)

If the browser did not open in the step above, use this method instead.

Open **PowerShell on Windows** (not inside WSL2) and run:

```powershell
winget install Rclone.Rclone
rclone authorize "drive"
```

A browser will open. Log in and grant access. PowerShell will print a JSON token:

```
Paste the following into your remote machine --->
{"access_token":"ya29.xxx","token_type":"Bearer","refresh_token":"1//xxx","expiry":"..."}
<---End paste
```

Copy the entire JSON block. Back in WSL2, when `rclone config` asks about the
browser, choose `n`. It will then prompt you to paste the token.

---

## Step 3 — Configure the `gdrive-crypt` remote (encrypted credentials)

This creates a second remote that transparently encrypts everything before
uploading. Files land inside `gdrive:Backups/WSL2/credentials` as unreadable
content with obfuscated filenames. Only someone with both passphrases can
decrypt them.

```bash
rclone config
```

```
n) New remote
name> gdrive-crypt
Storage> crypt
```

```
Remote to encrypt/decrypt.
remote> gdrive:Backups/WSL2/credentials
```

```
How to encrypt the filenames.
filename_encryption> 1    (standard — encrypts filenames)
```

```
Encrypt directory names?
directory_name_encryption> 1    (true)
```

You will be asked for two passphrases. **Save both in your password manager
before continuing** — without them your backups are permanently unreadable.

```
Password or pass phrase for encryption.
y/g> y
Enter the password:        ← first passphrase
Confirm the password:

Password or pass phrase for salt.
y/g/n> y
Enter the password:        ← second passphrase (salt)
Confirm the password:

Keep this "gdrive-crypt" remote? → y
```

**Verify:**

```bash
echo "test" | rclone rcat gdrive-crypt:test.txt
rclone ls gdrive-crypt:
rclone delete gdrive-crypt:test.txt
```

In Google Drive's web UI, look inside `Backups/WSL2/credentials/` — you should
see a file with a garbled name. That is correct.

---

## Step 4 — Protect the rclone config

The rclone config file at `~/.config/rclone/rclone.conf` holds your OAuth tokens.
Restrict its permissions:

```bash
chmod 600 ~/.config/rclone/rclone.conf
```

Optionally, encrypt the config file at rest by adding a passphrase to your shell
config. Add this to `~/.bashrc` or `~/.zshrc`:

```bash
export RCLONE_CONFIG_PASS="a-strong-passphrase"
```

Reload:

```bash
source ~/.bashrc   # or source ~/.zshrc
```

---

## Step 5 — Edit your backup config

```bash
nano ~/.config/wsl2-backup/config.sh
```

The defaults work if you named your remotes exactly `gdrive` and `gdrive-crypt`.
Key settings to review:

```bash
# Must match the names from steps 2 and 3
GDRIVE_REMOTE="gdrive"
GDRIVE_CRYPT_REMOTE="gdrive-crypt"

# Root folder path inside your Google Drive
GDRIVE_BACKUP_ROOT="Backups/WSL2"

# Override the auto-detected distro label (optional)
# DISTRO_LABEL="my-ubuntu"

# Additional directories to sync beyond ~/Documents (space-separated)
EXTRA_PATHS=""
# EXTRA_PATHS="$HOME/work $HOME/scripts"

# Upload parallelism — lower these if you hit Google Drive rate limit errors
RCLONE_TRANSFERS=8
RCLONE_CHECKERS=16
RCLONE_CHUNK_SIZE="256M"
```

Save and close.

---

## Step 6 — Dry run before the first real backup

This shows exactly what would be uploaded without transferring anything:

```bash
rclone sync ~/Documents gdrive:Backups/WSL2/dryrun-test \
  --filter-from ~/.config/rclone/wsl2-dev-filter.txt \
  --dry-run 2>&1 | head -80
```

Check that:
- `node_modules/`, `vendor/`, `obj/`, `bin/Debug/`, `go/pkg/` are **not** listed
- Your actual source files are listed
- The file count looks reasonable

If something unexpected is included, add an exclusion rule to
`~/.config/rclone/wsl2-dev-filter.txt` and re-run the dry run.

---

## Step 7 — Run the first backup

```bash
wsl2-backup
```

The first run uploads everything that passes the filter. Depending on how much
code you have, this can take anywhere from a few minutes to an hour. Every
subsequent run is incremental — only changed files are transferred.

Watch progress in real time:

```bash
tail -f ~/.local/share/wsl2-backup/backup.log
```

After it completes, verify in Google Drive. You should see:

```
Backups/
└── WSL2/
    └── ubuntu-24.04/
        ├── Documents/
        ├── config/
        ├── dotfiles/
        ├── local-bin/
        └── meta/
    credentials/          ← garbled filenames = correctly encrypted
```

---

## Step 8 — Verify the automated schedule

### If systemd is available (Ubuntu 22.04+ recommended)

```bash
systemctl --user status wsl2-backup.timer
```

Expected output:

```
● wsl2-backup.timer - Daily WSL2 Google Drive Backup
     Loaded: loaded; enabled
     Active: active (waiting)
    Trigger: tomorrow at 02:00
```

Useful commands:

```bash
# View logs from previous runs
journalctl --user -u wsl2-backup.service

# Trigger a backup manually right now
systemctl --user start wsl2-backup.service

# Disable the timer
systemctl --user disable --now wsl2-backup.timer
```

The timer uses `Persistent=true`, which means if your machine was off at 02:00,
the backup runs automatically on the next startup.

---

### Enable systemd in WSL2 (if not already on)

Check first:

```bash
systemctl --user status
```

If the command fails, systemd is not running. Enable it:

```bash
sudo nano /etc/wsl.conf
```

Add or confirm this content:

```ini
[boot]
systemd=true
```

Save, then from **PowerShell on Windows**:

```powershell
wsl --shutdown
```

Reopen WSL2, then re-run `install.sh` — it will now detect systemd and enable
the timer automatically.

---

### Cron fallback (if you prefer not to enable systemd)

```bash
crontab -e
```

Add this line:

```
0 2 * * * $HOME/.local/bin/wsl2-backup >> $HOME/.local/share/wsl2-backup/backup.log 2>&1
```

Note: the `cron` service itself must be running. On WSL2 without systemd, you
may need to start it manually or via `/etc/wsl.conf`:

```ini
[boot]
command = service cron start
```

---

### Windows Task Scheduler (alternative to systemd/cron)

This is the most reliable option when systemd is not available, because Windows
starts the task even if WSL2 was not running:

Open **PowerShell as Administrator** and run:

```powershell
$action = New-ScheduledTaskAction `
    -Execute "wsl.exe" `
    -Argument "-d Ubuntu-24.04 -e /home/<your-username>/.local/bin/wsl2-backup"

$trigger = New-ScheduledTaskTrigger -Daily -At "2:00AM"

$settings = New-ScheduledTaskSettingsSet `
    -RunOnlyIfNetworkAvailable `
    -StartWhenAvailable

Register-ScheduledTask `
    -TaskName "WSL2-GDrive-Backup" `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -RunLevel Highest
```

Replace `Ubuntu-24.04` with your actual distro name (check with `wsl --list`
in PowerShell) and `<your-username>` with your WSL2 username.

---

## Multiple distros

Each distro backs up independently to its own subfolder, named automatically
from `/etc/os-release` (e.g. `ubuntu-22.04`, `ubuntu-24.04`, `debian-12`).

**To add a second distro:**

1. The rclone OAuth token is reusable. Copy the config instead of re-authenticating:

   ```bash
   # Inside the already-configured distro
   cat ~/.config/rclone/rclone.conf
   ```

   In the new distro:

   ```bash
   mkdir -p ~/.config/rclone
   nano ~/.config/rclone/rclone.conf   # paste the contents
   chmod 600 ~/.config/rclone/rclone.conf
   ```

2. Run the installer — it detects the existing remotes and skips auth:

   ```bash
   curl -sL https://raw.githubusercontent.com/sosalejandro/wsl2-backup/main/install.sh | bash
   ```

**To back up all distros from Windows Task Scheduler:**

```powershell
# backup-all-distros.ps1
$distros = @("Ubuntu-22.04", "Ubuntu-24.04")

foreach ($distro in $distros) {
    Write-Host "Backing up: $distro"
    wsl.exe -d $distro -e /home/<your-username>/.local/bin/wsl2-backup
}
```

Credentials (`~/.ssh`, `~/.aws`, etc.) are typically identical across distros.
Back them up from your primary distro only to avoid redundant uploads.

---

## File locations reference

| Path | Purpose |
|---|---|
| `~/.config/rclone/rclone.conf` | rclone remotes and OAuth tokens |
| `~/.config/rclone/wsl2-dev-filter.txt` | exclude rules — edit to customize |
| `~/.config/wsl2-backup/config.sh` | your backup preferences |
| `~/.local/bin/wsl2-backup` | the backup command |
| `~/.local/share/wsl2-backup/backup.log` | run logs |
| `~/.local/share/wsl2-backup/meta/` | captured env metadata |
| `~/.config/systemd/user/wsl2-backup.timer` | daily schedule |
| `~/.config/systemd/user/wsl2-backup.service` | systemd service unit |

---

## Uninstall

```bash
bash uninstall.sh
```

Removes the backup command, filter file, systemd units, and optionally your
config. rclone itself and all Google Drive backups are left untouched.

---

## License

MIT
