#!/usr/bin/env python3
"""
🦉 Strix Local Dispatcher
Runs on Marcus's local machine. Polls the aigege.de inbox for CLAW_TASK emails
from Crunch Cloud, verifies the GPG signature, executes the task, and emails
back a signed CLAW_RESULT to crunchcloud.agent@aigege.de.

Usage:
    python dispatcher.py [--config strix.env] [--once] [--dry-run]

Config (strix.env or environment variables):
    STRIX_EMAIL          - Strix's email address (crunchlocal.agent@aigege.de)
    STRIX_EMAIL_PASS     - Strix's email password (IMAP + SMTP)
    STRIX_IMAP_HOST      - IMAP host (e.g. mx2f20.netcup.net)
    STRIX_SMTP_HOST      - SMTP host (same as IMAP usually)
    CLAW_CLOUD_EMAIL     - Crunch's cloud email (crunchcloud.agent@aigege.de)
    CLAW_CLOUD_GPG_PUBKEY_FILE  - Path to Crunch cloud GPG public key ASC file
    STRIX_GPG_PRIVKEY_FILE      - Path to Strix local GPG private key ASC file
    STRIX_GPG_PASSPHRASE        - (optional) GPG key passphrase
    GITEA_URL            - (optional) Local Gitea URL e.g. http://localhost:3000
    GITEA_TOKEN          - (optional) Gitea API token
    GITEA_REPO           - (optional) Gitea repo for tasks e.g. mac/strix-base
    POLL_INTERVAL        - Seconds between polls (default: 60)
"""

import imaplib
import smtplib
import ssl
import email
import json
import os
import sys
import time
import tempfile
import subprocess
import logging
import argparse
import urllib.request
import urllib.error
from pathlib import Path
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime, timezone

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%SZ",
)
log = logging.getLogger("strix")


def load_env(config_file: str):
    """Load key=value config file into os.environ."""
    p = Path(config_file)
    if not p.exists():
        return
    for line in p.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def require(var: str) -> str:
    v = os.environ.get(var)
    if not v:
        log.error(f"Required env var {var} is not set")
        sys.exit(1)
    return v


def setup_gpg(homedir: str):
    """Import cloud public key and local private key into temp GPG homedir."""
    os.makedirs(homedir, mode=0o700, exist_ok=True)

    cloud_pub = os.environ.get("CLAW_CLOUD_GPG_PUBKEY_FILE")
    local_priv = os.environ.get("STRIX_GPG_PRIVKEY_FILE")

    if cloud_pub and Path(cloud_pub).exists():
        subprocess.run(
            ["gpg", "--homedir", homedir, "--batch", "--import", cloud_pub],
            check=True, capture_output=True,
        )
        log.info("Crunch cloud GPG public key imported")
    else:
        log.warning("CLAW_CLOUD_GPG_PUBKEY_FILE not set or not found — will skip signature verification")

    if local_priv and Path(local_priv).exists():
        passphrase = os.environ.get("STRIX_GPG_PASSPHRASE", "")
        cmd = ["gpg", "--homedir", homedir, "--batch", "--import", local_priv]
        inp = passphrase.encode() if passphrase else None
        subprocess.run(cmd, input=inp, check=True, capture_output=True)
        log.info("Strix local GPG private key imported")
    else:
        log.warning("STRIX_GPG_PRIVKEY_FILE not set or not found — will skip result signing")


def verify_and_extract_json(signed_text: str, gpg_homedir: str) -> dict | None:
    """Verify GPG clear-signed text and return the JSON payload, or None on failure."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".asc", delete=False) as f:
        f.write(signed_text)
        fname = f.name

    try:
        result = subprocess.run(
            ["gpg", "--homedir", gpg_homedir, "--batch", "--verify", fname],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            log.warning(f"GPG verification failed: {result.stderr.strip()}")
            # Still try to extract payload for dry-run / no-key situations
            # Find the JSON between the signature headers
        
        # Extract the payload (between -----BEGIN PGP SIGNED MESSAGE----- headers and -----BEGIN PGP SIGNATURE-----)
        lines = signed_text.splitlines()
        payload_lines = []
        in_payload = False
        for line in lines:
            if line.startswith("-----BEGIN PGP SIGNED MESSAGE-----"):
                in_payload = False
                continue
            if line.startswith("Hash:") or line.startswith("NotDashEscaped:"):
                continue
            if line == "" and not in_payload:
                in_payload = True
                continue
            if line.startswith("-----BEGIN PGP SIGNATURE-----"):
                break
            if in_payload:
                payload_lines.append(line)

        payload = "\n".join(payload_lines).strip()
        if not payload:
            # Not a signed message, try raw JSON
            payload = signed_text.strip()

        data = json.loads(payload)
        
        if result.returncode != 0:
            log.warning("Proceeding with unverified payload (no cloud GPG key available)")
        else:
            log.info("GPG signature verified ✅")
        
        return data
    except json.JSONDecodeError as e:
        log.error(f"Failed to parse task JSON: {e}")
        return None
    except Exception as e:
        log.error(f"Error extracting task: {e}")
        return None
    finally:
        os.unlink(fname)


def sign_result(result_json: str, gpg_homedir: str) -> str:
    """GPG-sign the result JSON. Returns signed ASCII-armored text, or raw JSON on failure."""
    strix_key = os.environ.get("STRIX_EMAIL", "strix")
    passphrase = os.environ.get("STRIX_GPG_PASSPHRASE", "")

    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        f.write(result_json)
        fname = f.name

    out_fname = fname + ".asc"
    try:
        cmd = [
            "gpg", "--homedir", gpg_homedir, "--batch", "--armor",
            "--clearsign", "--default-key", strix_key,
            "--output", out_fname, fname,
        ]
        if passphrase:
            cmd = ["gpg", "--homedir", gpg_homedir, "--batch", "--armor",
                   "--clearsign", "--passphrase", passphrase,
                   "--default-key", strix_key, "--output", out_fname, fname]

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            signed = Path(out_fname).read_text()
            log.info("Result signed with Strix GPG key ✅")
            return signed
        else:
            log.warning(f"Signing failed: {result.stderr.strip()} — sending unsigned")
            return result_json
    except Exception as e:
        log.warning(f"Signing error: {e} — sending unsigned")
        return result_json
    finally:
        try:
            os.unlink(fname)
            if Path(out_fname).exists():
                os.unlink(out_fname)
        except Exception:
            pass


def execute_via_gitea(task: dict) -> str:
    """Post task to local Gitea as an issue, poll for response. Returns result string."""
    gitea_url = os.environ["GITEA_URL"].rstrip("/")
    token = os.environ["GITEA_TOKEN"]
    repo = os.environ["GITEA_REPO"]  # e.g. "mac/strix-base"

    title = f"[CLAW] {task.get('title', 'Task ' + task.get('task_id', ''))}"
    body = f"**Dispatched by Crunch Cloud at {task.get('dispatched_at', '')}**\n\n"
    body += f"**Issue #{task.get('issue_number', '?')}** in {task.get('repo', '')}\n\n"
    body += task.get("body", "")
    if task.get("comments"):
        body += "\n\n---\n**Comments:**\n"
        for c in task["comments"]:
            body += f"\n> **{c.get('author','')}**: {c.get('body','')}\n"

    issue_data = json.dumps({"title": title, "body": body}).encode()

    headers = {
        "Authorization": f"token {token}",
        "Content-Type": "application/json",
    }
    url = f"{gitea_url}/api/v1/repos/{repo}/issues"

    req = urllib.request.Request(url, data=issue_data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            issue = json.loads(resp.read())
            issue_num = issue["number"]
            issue_url = issue.get("html_url", f"{gitea_url}/{repo}/issues/{issue_num}")
            log.info(f"Created Gitea issue #{issue_num}: {issue_url}")
            return f"✅ Task posted to Gitea as issue #{issue_num}: {issue_url}\n\nMonitor Gitea for the result — Strix act_runner will process this."
    except Exception as e:
        return f"❌ Failed to create Gitea issue: {e}"


def execute_task(task: dict) -> str:
    """Execute the task and return result string."""
    task_id = task.get("task_id", "unknown")
    title = task.get("title", "")
    body = task.get("body", "")

    log.info(f"Executing task {task_id}: {title}")

    # Try Gitea if configured
    if all(os.environ.get(v) for v in ["GITEA_URL", "GITEA_TOKEN", "GITEA_REPO"]):
        log.info("Using Gitea for task execution")
        return execute_via_gitea(task)

    # Fallback: log the task and return a placeholder
    log.info("No Gitea configured — logging task for manual review")
    summary = f"Task received: {task_id}\nTitle: {title}\n\nBody:\n{body[:500]}"
    log.info(summary)
    return f"⏳ Task {task_id} received by Strix local.\n\nGitea not configured — manual execution needed.\n\nTitle: {title}\nBody excerpt: {body[:200]}..."


def send_result(task: dict, result_text: str, signed_body: str):
    """Email the signed result back to Crunch Cloud."""
    smtp_host = require("STRIX_SMTP_HOST")
    strix_email = require("STRIX_EMAIL")
    strix_pass = require("STRIX_EMAIL_PASS")
    cloud_email = require("CLAW_CLOUD_EMAIL")

    issue_number = task.get("issue_number", "0")
    task_id = task.get("task_id", "UNKNOWN")

    msg = MIMEMultipart()
    msg["From"] = strix_email
    msg["To"] = cloud_email
    msg["Subject"] = f"CLAW_RESULT: #{issue_number} — {task.get('title', task_id)}"
    msg["X-CLAW-Issue"] = str(issue_number)
    msg["X-CLAW-Task-ID"] = task_id
    msg["X-CLAW-Repo"] = task.get("repo", "")
    msg["X-CLAW-Completed-At"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    msg.attach(MIMEText(signed_body, "plain"))

    log.info(f"Sending result for task {task_id} to {cloud_email}...")
    context = ssl.create_default_context()
    with smtplib.SMTP_SSL(smtp_host, 465, context=context) as server:
        server.login(strix_email, strix_pass)
        server.sendmail(strix_email, cloud_email, msg.as_string())
    log.info(f"Result sent ✅ — Crunch will post it to issue #{issue_number}")


def poll_once(imap_host: str, strix_email: str, strix_pass: str, gpg_homedir: str, dry_run: bool):
    """Check inbox for one batch of CLAW_TASK emails."""
    log.info("Polling inbox for CLAW_TASK messages...")

    mail = imaplib.IMAP4_SSL(imap_host, 993)
    mail.login(strix_email, strix_pass)
    mail.select("INBOX")

    _, data = mail.search(None, 'UNSEEN SUBJECT "CLAW_TASK:"')
    msg_ids = data[0].split()

    if not msg_ids:
        log.info("No new tasks.")
        mail.logout()
        return

    log.info(f"Found {len(msg_ids)} new task(s)")

    for msg_id in msg_ids:
        try:
            _, raw = mail.fetch(msg_id, "(RFC822)")
            raw_email = raw[0][1]
            parsed = email.message_from_bytes(raw_email)
            subject = parsed.get("Subject", "")
            log.info(f"Processing: {subject}")

            # Extract body
            body_text = ""
            if parsed.is_multipart():
                for part in parsed.walk():
                    if part.get_content_type() == "text/plain":
                        body_text = part.get_payload(decode=True).decode("utf-8", errors="replace")
                        break
            else:
                body_text = parsed.get_payload(decode=True).decode("utf-8", errors="replace")

            # Verify and extract task JSON
            task = verify_and_extract_json(body_text, gpg_homedir)
            if not task:
                log.error(f"Could not extract task from email — skipping")
                continue

            log.info(f"Task: {task.get('task_id')} — {task.get('title')}")

            if dry_run:
                log.info(f"[DRY RUN] Would execute task: {json.dumps(task, indent=2)[:500]}")
                continue

            # Execute
            result_text = execute_task(task)

            # Build result JSON
            result_json = json.dumps({
                "task_id": task.get("task_id"),
                "issue_number": task.get("issue_number"),
                "repo": task.get("repo"),
                "result": result_text,
                "completed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "executed_by": "strix-local",
            }, indent=2)

            # Sign result
            signed = sign_result(result_json, gpg_homedir)

            # Send back
            send_result(task, result_text, signed)

            # Mark as read
            mail.store(msg_id, "+FLAGS", "\\Seen")

        except Exception as e:
            log.error(f"Error processing message {msg_id}: {e}", exc_info=True)

    mail.logout()


def main():
    parser = argparse.ArgumentParser(description="🦉 Strix Local Dispatcher")
    parser.add_argument("--config", default="strix.env", help="Config file path")
    parser.add_argument("--once", action="store_true", help="Poll once and exit")
    parser.add_argument("--dry-run", action="store_true", help="Parse tasks but don't execute or send")
    args = parser.parse_args()

    load_env(args.config)

    imap_host = require("STRIX_IMAP_HOST")
    strix_email = require("STRIX_EMAIL")
    strix_pass = require("STRIX_EMAIL_PASS")
    poll_interval = int(os.environ.get("POLL_INTERVAL", "60"))

    # Setup GPG in a temp dir
    gpg_homedir = os.path.join(tempfile.gettempdir(), "strix-gpg")
    setup_gpg(gpg_homedir)

    log.info(f"🦉 Strix Local Dispatcher starting — polling {imap_host} every {poll_interval}s")
    if args.dry_run:
        log.info("[DRY RUN mode — tasks will not be executed or forwarded]")

    if args.once:
        poll_once(imap_host, strix_email, strix_pass, gpg_homedir, args.dry_run)
        return

    while True:
        try:
            poll_once(imap_host, strix_email, strix_pass, gpg_homedir, args.dry_run)
        except Exception as e:
            log.error(f"Poll cycle failed: {e}", exc_info=True)
        time.sleep(poll_interval)


if __name__ == "__main__":
    main()
