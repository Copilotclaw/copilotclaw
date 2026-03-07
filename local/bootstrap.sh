#!/usr/bin/env bash
# bootstrap.sh — from bare Ubuntu 24.04 to Crunch-ready VPS
# Usage: curl -fsSL https://raw.githubusercontent.com/Copilotclaw/copilotclaw/main/local/bootstrap.sh | bash
# Or:   bash local/bootstrap.sh
#
# What it does:
#   1. Base system setup (apt, ufw, fail2ban)
#   2. Docker + docker-compose
#   3. Gitea (SQLite, docker-compose)
#   4. Gitea Act Runner
#   5. Caddy (auto-TLS)
#   6. Claude CLI (Node.js + npm)
#   7. UFW rules (22/443 only)
#   8. Prompt for GitHub token + add to Gitea
#   9. Writes /root/crunch-setup-summary.txt

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[crunch]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
die()     { echo -e "${RED}[✗]${NC} $*"; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root: sudo bash bootstrap.sh"

GITEA_DOMAIN=""
GITEA_ADMIN_USER="crunch"
GITEA_ADMIN_PASS=""
GH_TOKEN_VALUE=""
SETUP_SUMMARY="/root/crunch-setup-summary.txt"

# ─── Collect config upfront ──────────────────────────────────────────────────

echo ""
echo "🦃 Crunch VPS Bootstrap"
echo "━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -rp "Domain for Gitea (e.g. git.yourdomain.com): " GITEA_DOMAIN
[[ -n "$GITEA_DOMAIN" ]] || die "Domain is required"

read -rsp "Gitea admin password (you'll use this to log in): " GITEA_ADMIN_PASS
echo ""
[[ -n "$GITEA_ADMIN_PASS" ]] || die "Password is required"

read -rsp "GitHub token (COPILOT_PAT — paste here): " GH_TOKEN_VALUE
echo ""
[[ -n "$GH_TOKEN_VALUE" ]] || warn "No token provided — you'll need to add it manually later"

echo ""
info "Starting setup. This takes ~5 minutes."
echo ""

# ─── 1. Base packages ─────────────────────────────────────────────────────────

info "1/9 — Base packages"
apt-get update -qq
apt-get install -y -qq \
    curl git wget unzip vim \
    ufw fail2ban \
    ca-certificates gnupg lsb-release \
    jq htop ncdu 2>/dev/null
success "Base packages installed"

# ─── 2. Docker ────────────────────────────────────────────────────────────────

info "2/9 — Docker"
if ! command -v docker &>/dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable --now docker
    success "Docker installed"
else
    success "Docker already present"
fi

# ─── 3. Directories ───────────────────────────────────────────────────────────

info "3/9 — Creating directories"
mkdir -p /opt/crunch/{gitea,caddy,runner}
mkdir -p /opt/crunch/gitea/{data,config}
success "Directories ready at /opt/crunch/"

# ─── 4. Gitea + Caddy via docker-compose ──────────────────────────────────────

info "4/9 — Gitea + Caddy"
cat > /opt/crunch/docker-compose.yml <<EOF
version: '3.8'

networks:
  crunch:
    driver: bridge

services:
  gitea:
    image: gitea/gitea:latest
    container_name: gitea
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - GITEA__database__DB_TYPE=sqlite3
      - GITEA__server__DOMAIN=${GITEA_DOMAIN}
      - GITEA__server__ROOT_URL=https://${GITEA_DOMAIN}/
      - GITEA__server__HTTP_PORT=3000
      - GITEA__service__DISABLE_REGISTRATION=true
      - GITEA__service__REQUIRE_SIGNIN_VIEW=false
    volumes:
      - /opt/crunch/gitea/data:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "127.0.0.1:3000:3000"
      - "22:22"
    networks:
      - crunch
    restart: unless-stopped

  caddy:
    image: caddy:latest
    container_name: caddy
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /opt/crunch/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_certs:/root/.local/share/caddy
    networks:
      - crunch
    restart: unless-stopped

volumes:
  caddy_data:
  caddy_certs:
EOF

cat > /opt/crunch/caddy/Caddyfile <<EOF
${GITEA_DOMAIN} {
    reverse_proxy gitea:3000
}
EOF

cd /opt/crunch
docker compose up -d gitea caddy
success "Gitea + Caddy started"

# ─── 5. Wait for Gitea to be ready ───────────────────────────────────────────

info "5/9 — Waiting for Gitea to initialize (~30s)"
for i in $(seq 1 30); do
    if curl -sf http://127.0.0.1:3000/api/healthz &>/dev/null; then
        success "Gitea is up"
        break
    fi
    sleep 2
    [[ $i -eq 30 ]] && die "Gitea didn't start in 60s — check: docker logs gitea"
done

# Create admin user
info "Creating Gitea admin user: ${GITEA_ADMIN_USER}"
docker exec gitea gitea admin user create \
    --admin \
    --username "${GITEA_ADMIN_USER}" \
    --password "${GITEA_ADMIN_PASS}" \
    --email "crunch@${GITEA_DOMAIN}" \
    --must-change-password=false 2>/dev/null || warn "Admin user may already exist"

# Generate Gitea API token for local use
GITEA_TOKEN=$(docker exec gitea gitea admin user generate-access-token \
    --username "${GITEA_ADMIN_USER}" \
    --token-name "bootstrap" \
    --raw 2>/dev/null | grep -oP '[a-f0-9]{40}' | head -1 || true)
success "Gitea admin created"

# ─── 6. Gitea Act Runner ──────────────────────────────────────────────────────

info "6/9 — Gitea Act Runner"
RUNNER_VERSION=$(curl -sf https://gitea.com/api/v1/repos/gitea/act_runner/releases/latest \
    | jq -r .tag_name 2>/dev/null || echo "v0.2.11")
RUNNER_BIN="/usr/local/bin/act_runner"

if [[ ! -f "$RUNNER_BIN" ]]; then
    ARCH=$(dpkg --print-architecture)
    [[ "$ARCH" == "amd64" ]] && ARCH="amd64" || ARCH="arm64"
    curl -fsSL \
        "https://gitea.com/gitea/act_runner/releases/download/${RUNNER_VERSION}/act_runner-${RUNNER_VERSION}-linux-${ARCH}" \
        -o "$RUNNER_BIN"
    chmod +x "$RUNNER_BIN"
fi

# Get runner registration token
RUNNER_TOKEN=$(curl -sf \
    -H "Authorization: token ${GITEA_TOKEN}" \
    "http://127.0.0.1:3000/api/v1/admin/runners/registration-token" \
    | jq -r .token 2>/dev/null || true)

if [[ -n "$RUNNER_TOKEN" ]]; then
    mkdir -p /opt/crunch/runner
    act_runner register \
        --instance "http://127.0.0.1:3000" \
        --token "$RUNNER_TOKEN" \
        --name "vps-runner-1" \
        --labels "ubuntu-latest:docker://node:20-bookworm-slim,ubuntu-22.04:docker://node:20-bookworm-slim" \
        --no-interactive \
        --config /opt/crunch/runner/config.yaml 2>/dev/null || true

    # systemd service
    cat > /etc/systemd/system/act-runner.service <<'EOF'
[Unit]
Description=Gitea Act Runner
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/crunch/runner
ExecStart=/usr/local/bin/act_runner daemon --config /opt/crunch/runner/config.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now act-runner
    success "Act Runner registered and running"
else
    warn "Could not get runner token — register manually later with: act_runner register"
fi

# ─── 7. Claude CLI ────────────────────────────────────────────────────────────

info "7/9 — Claude CLI (Node.js)"
if ! command -v node &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y -qq nodejs
fi
npm install -g @anthropic-ai/claude-code 2>/dev/null || \
    warn "Claude CLI install failed — run: npm install -g @anthropic-ai/claude-code"
success "Claude CLI installed (run 'claude' to authenticate)"

# ─── 8. UFW firewall ──────────────────────────────────────────────────────────

info "8/9 — UFW firewall"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    comment 'SSH'
ufw allow 80/tcp    comment 'HTTP (Caddy redirect)'
ufw allow 443/tcp   comment 'HTTPS (Gitea)'
ufw --force enable
success "UFW: only 22/80/443 open"

# Fail2ban
systemctl enable --now fail2ban
success "Fail2ban active"

# ─── 9. GitHub token → Gitea repo secret ─────────────────────────────────────

info "9/9 — Store GitHub token as Gitea secret"
if [[ -n "$GH_TOKEN_VALUE" && -n "$GITEA_TOKEN" ]]; then
    # Create copilotclaw mirror repo in Gitea for secrets
    curl -sf -X POST \
        -H "Authorization: token ${GITEA_TOKEN}" \
        -H "Content-Type: application/json" \
        "http://127.0.0.1:3000/api/v1/user/repos" \
        -d '{"name":"copilotclaw","private":false,"auto_init":true}' &>/dev/null || true

    # Add GH_TOKEN secret
    curl -sf -X PUT \
        -H "Authorization: token ${GITEA_TOKEN}" \
        -H "Content-Type: application/json" \
        "http://127.0.0.1:3000/api/v1/repos/${GITEA_ADMIN_USER}/copilotclaw/actions/secrets/GH_TOKEN" \
        -d "{\"data\":\"${GH_TOKEN_VALUE}\"}" &>/dev/null && \
        success "GH_TOKEN stored as Gitea secret" || \
        warn "Could not store GH_TOKEN — add manually in Gitea Settings → Secrets"
fi

# ─── Summary ──────────────────────────────────────────────────────────────────

cat > "$SETUP_SUMMARY" <<EOF
🦃 Crunch VPS Setup Summary
Generated: $(date -u '+%Y-%m-%d %H:%M UTC')
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Gitea URL:     https://${GITEA_DOMAIN}/
Admin user:    ${GITEA_ADMIN_USER}
Admin pass:    [stored in your head — not written here for security]
SSH clone:     ssh://git@${GITEA_DOMAIN}:22/<repo>.git

Docker stack:  /opt/crunch/docker-compose.yml
  - docker compose -f /opt/crunch/docker-compose.yml ps
  - docker compose -f /opt/crunch/docker-compose.yml logs gitea

Act Runner:    systemctl status act-runner
  - Registered as: vps-runner-1
  - Labels: ubuntu-latest, ubuntu-22.04

Claude CLI:    claude --version (authenticate with: claude)

UFW rules:
  - 22/tcp  (SSH)
  - 80/tcp  (HTTP → 443 redirect)
  - 443/tcp (HTTPS)

Register more runners:
  act_runner register --instance https://${GITEA_DOMAIN} --token <token>
  (Get token: Gitea → Site Admin → Runners → Registration Token)

Check logs:
  docker logs gitea --tail 50
  docker logs caddy --tail 50
  journalctl -u act-runner -f

Next steps:
  1. Run: claude   (authenticate Claude CLI)
  2. Mirror Copilotclaw/copilotclaw to Gitea
  3. Add GH_TOKEN secret if not already added
  4. Test: push a commit and watch the runner pick it up
EOF

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🦃 Setup complete!${NC}"
echo ""
echo "  Gitea:   https://${GITEA_DOMAIN}/"
echo "  Summary: $SETUP_SUMMARY"
echo ""
echo "  Run 'claude' to authenticate Claude CLI"
echo "  Run 'cat $SETUP_SUMMARY' to review setup"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
