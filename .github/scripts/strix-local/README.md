# 🦉 Strix Local Dispatcher

Strix is Crunch's local agent. When Marcus labels a GitHub issue with `dispatch/local`, the task is GPG-signed and emailed to Strix's inbox. Strix picks it up, executes it, and emails back a signed result which gets posted to the original issue.

## Architecture

```
GitHub Issue (dispatch/local label)
       ↓
dispatch-local.yml (GitHub Actions, cloud)
  → Signs task JSON with Crunch GPG key
  → Emails to crunchlocal.agent@aigege.de
       ↓
dispatcher.py (Marcus's local machine) ← YOU ARE HERE
  → Verifies Crunch's GPG signature
  → Executes task (Gitea or standalone)
  → Signs result with Strix GPG key
  → Emails to crunchcloud.agent@aigege.de
       ↓
recv-local.yml (GitHub Actions, cloud, polls every 5min)
  → Verifies Strix's GPG signature
  → Posts result to original GitHub issue
```

## First-Time Setup

### 1. Clone this repo (once)

```bash
# On your local machine:
git clone https://github.com/Copilotclaw/copilotclaw.git
cd copilotclaw/.github/scripts/strix-local
```

### 2. Get the GPG keys

Both keys are stored in `Copilotclaw/private/credentials/gpg/`. Ask Crunch to fetch them, or:

```bash
gh api repos/Copilotclaw/private/contents/credentials/gpg/crunch-cloud-public.asc \
  --jq '.content' | base64 -d > keys/crunch-cloud-public.asc

gh api repos/Copilotclaw/private/contents/credentials/gpg/strix-local-private.asc \
  --jq '.content' | base64 -d > keys/strix-local-private.asc
```

### 3. Run the installer

```bash
bash install.sh
```

This installs dependencies, creates `strix.env`, and optionally sets up a systemd service.

### 4. Fill in `strix.env`

Open `strix.env` and set `STRIX_EMAIL_PASS` (Strix's email password from Copilotclaw/private).

### 5. Test it

```bash
# Dry run — verifies setup without sending anything
python3 dispatcher.py --once --dry-run

# Start the daemon
python3 dispatcher.py
```

### 6. (Optional) Gitea integration

If you're running Gitea + act_runner locally, set these in `strix.env`:

```
GITEA_URL=http://localhost:3000
GITEA_TOKEN=<your gitea API token>
GITEA_REPO=mac/strix-base
```

When configured, tasks are posted as Gitea issues and the act_runner runs them through a full Copilot CLI agent.

## Windows (WSL)

Install WSL, then run everything inside WSL:

```
wsl
cd /mnt/c/Users/YOU/copilotclaw/.github/scripts/strix-local
bash install.sh
python3 dispatcher.py
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `STRIX_EMAIL` | ✅ | — | Strix's email address |
| `STRIX_EMAIL_PASS` | ✅ | — | Strix's email password |
| `STRIX_IMAP_HOST` | ✅ | — | IMAP server hostname |
| `STRIX_SMTP_HOST` | ✅ | — | SMTP server hostname |
| `CLAW_CLOUD_EMAIL` | ✅ | — | Crunch cloud email |
| `CLAW_CLOUD_GPG_PUBKEY_FILE` | ⚠️ | — | Path to Crunch's public GPG key |
| `STRIX_GPG_PRIVKEY_FILE` | ⚠️ | — | Path to Strix's private GPG key |
| `STRIX_GPG_PASSPHRASE` | — | — | GPG key passphrase (if any) |
| `GITEA_URL` | — | — | Local Gitea URL |
| `GITEA_TOKEN` | — | — | Gitea API token |
| `GITEA_REPO` | — | — | Gitea repo (owner/name) |
| `POLL_INTERVAL` | — | `60` | Seconds between inbox polls |

## Trigger a test

In GitHub, add the `dispatch/local` label to any issue. Watch:

1. `dispatch-local.yml` runs and emails Strix
2. `dispatcher.py` picks up the email (within POLL_INTERVAL seconds)
3. `recv-local.yml` picks up the result (within 5 minutes)
4. Result appears as a comment on the original issue

---

🦃↔️🦉 Crunch Cloud ↔ Strix Local
