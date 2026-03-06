#!/usr/bin/env bash
# install.sh — Set up Strix Local Dispatcher on Marcus's machine
# Run once from .github/scripts/strix-local/
# Works on Linux, macOS, and WSL on Windows

set -euo pipefail

echo "🦉 Strix Local Dispatcher — Installation"
echo "========================================="

# Detect OS
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    echo "⚠️  Windows native detected. Use WSL for best results."
    echo "   Run: wsl bash install.sh"
fi

# Install Python dependencies
echo ""
echo "📦 Installing Python dependencies..."
pip3 install python-gnupg 2>/dev/null || pip install python-gnupg

# Check GPG
if ! command -v gpg &>/dev/null; then
    echo "⚠️  GPG not found. Installing..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get install -y gpg
    elif command -v brew &>/dev/null; then
        brew install gnupg
    else
        echo "❌ Cannot auto-install GPG. Please install it manually."
        exit 1
    fi
fi

echo "✅ GPG available: $(gpg --version | head -1)"

# Create config template
CONFIG_FILE="strix.env"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo ""
    echo "📝 Creating config template: $CONFIG_FILE"
    cat > "$CONFIG_FILE" <<'EOF'
# Strix local email (crunchlocal.agent@aigege.de)
STRIX_EMAIL=crunchlocal.agent@aigege.de
STRIX_EMAIL_PASS=

# Mail server (aigege.de is on netcup)
STRIX_IMAP_HOST=mx2f20.netcup.net
STRIX_SMTP_HOST=mx2f20.netcup.net

# Crunch Cloud email (send results here)
CLAW_CLOUD_EMAIL=crunchcloud.agent@aigege.de

# GPG key paths (relative to this directory)
CLAW_CLOUD_GPG_PUBKEY_FILE=keys/crunch-cloud-public.asc
STRIX_GPG_PRIVKEY_FILE=keys/strix-local-private.asc
# STRIX_GPG_PASSPHRASE=

# Optional Gitea integration (local act_runner)
# GITEA_URL=http://localhost:3000
# GITEA_TOKEN=
# GITEA_REPO=mac/strix-base

# Poll every 60 seconds
POLL_INTERVAL=60
EOF
    echo "✅ Created $CONFIG_FILE — fill in your passwords before running dispatcher.py"
else
    echo "✅ Config file already exists: $CONFIG_FILE"
fi

# Create keys directory
mkdir -p keys
echo ""
echo "🔑 Key setup:"
echo "   Place Crunch's cloud GPG public key at:  keys/crunch-cloud-public.asc"
echo "   Place Strix's local GPG private key at:  keys/strix-local-private.asc"
echo ""
echo "   Both key files are stored in Copilotclaw/private on GitHub."
echo "   Ask Crunch to fetch them for you, or download from the private repo."
echo ""

# Create systemd service (Linux/WSL)
if command -v systemctl &>/dev/null; then
    echo "💡 To run as a background service (Linux/WSL):"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cat <<EOF

    sudo tee /etc/systemd/system/strix-dispatcher.service > /dev/null <<SVCEOF
[Unit]
Description=Strix Local Dispatcher
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$SCRIPT_DIR
ExecStart=$(which python3) $SCRIPT_DIR/dispatcher.py
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
SVCEOF

    sudo systemctl daemon-reload
    sudo systemctl enable strix-dispatcher
    sudo systemctl start strix-dispatcher
EOF
fi

echo "🚀 To run manually:"
echo "   python3 dispatcher.py --config strix.env"
echo ""
echo "🔎 To test without sending anything:"
echo "   python3 dispatcher.py --config strix.env --dry-run --once"
echo ""
echo "✅ Strix install complete."
