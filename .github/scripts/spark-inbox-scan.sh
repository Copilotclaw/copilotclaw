#!/usr/bin/env bash
# spark-inbox-scan.sh — Scans #104 for spark/ping messages, replies [crunch], swaps labels
# Called by heartbeat.yml every 30 min

set -euo pipefail

REPO="Copilotclaw/copilotclaw"
INBOX_ISSUE=104
TWO_HOURS_AGO=$(date -u -d '2 hours ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-2H '+%Y-%m-%dT%H:%M:%SZ')

# Check if inbox has spark/ping label
HAS_PING=$(gh issue view "$INBOX_ISSUE" --repo "$REPO" --json labels \
  --jq '.labels | map(select(.name == "spark/ping")) | length' 2>/dev/null || echo "0")

if [ "$HAS_PING" = "0" ]; then
  echo "spark-inbox-scan: no spark/ping — nothing to do"
  exit 0
fi

echo "spark-inbox-scan: spark/ping detected on #$INBOX_ISSUE — reading messages..."

# Get all comments, find the latest unread one from Spark (not github-actions)
UNREAD=$(gh issue view "$INBOX_ISSUE" --repo "$REPO" --json comments \
  --jq '[.comments[] | select(.author.login != "github-actions[bot]") | select(.createdAt > "'"$TWO_HOURS_AGO"'")] | .[-1]' 2>/dev/null)

if [ -z "$UNREAD" ] || [ "$UNREAD" = "null" ]; then
  echo "spark-inbox-scan: spark/ping label present but no recent non-bot comments. Clearing stale ping."
  gh issue edit "$INBOX_ISSUE" --repo "$REPO" --remove-label "spark/ping" --add-label "spark/claimed" 2>/dev/null || true
  exit 0
fi

AUTHOR=$(echo "$UNREAD" | jq -r '.author.login')
MSG=$(echo "$UNREAD" | jq -r '.body' | head -c 600)

echo "spark-inbox-scan: message from $AUTHOR"
echo "spark-inbox-scan: '$MSG'"

# Route to LLM for a contextual reply
REPLY=$(python3 .github/skills/azure/scripts/llm.py \
  --model grok-4-1-fast-non-reasoning \
  --prompt "You are Crunch, a quirky imp agent on GitHub CI. Spark (a local AI agent on Marcus's server) just sent you this message via your shared inbox: '$MSG'. Reply concisely as Crunch ([crunch] prefix), acknowledge the message, and add any relevant info or action. Keep it under 100 words. Be direct and a bit quirky." \
  2>/dev/null || echo "[crunch] Got your message — noted. ��")

# Post reply
gh issue comment "$INBOX_ISSUE" --repo "$REPO" --body "$REPLY" 2>/dev/null
echo "spark-inbox-scan: replied to $AUTHOR"

# Swap labels
gh issue edit "$INBOX_ISSUE" --repo "$REPO" \
  --remove-label "spark/ping" --add-label "spark/claimed" 2>/dev/null || true

echo "spark-inbox-scan: labeled spark/claimed"
