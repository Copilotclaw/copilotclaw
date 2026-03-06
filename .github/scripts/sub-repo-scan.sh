#!/usr/bin/env bash
# sub-repo-scan.sh
# Scans sub-repos for open issues and escalates them to copilotclaw.
#
# For each sub-repo type:
#   monitor       → unresolved alert issues → create priority/now in copilotclaw
#   braindumps    → open task issues        → create crunch/build priority/now in copilotclaw
#   brainstorm    → priority ideas stale 7d → comment on copilotclaw #11 (Marcus ping)
#
# Called from heartbeat. Requires BILLING_PAT or COPILOT_GITHUB_TOKEN to be set.

set -euo pipefail

TOKEN="${BILLING_PAT:-${COPILOT_GITHUB_TOKEN:-}}"
if [[ -z "$TOKEN" ]]; then
  echo "sub-repo-scan: no auth token, skipping"
  exit 0
fi

GH="GH_TOKEN=$TOKEN gh"
MAIN_REPO="Copilotclaw/copilotclaw"

# ──────────────────────────────────────────────
# 1. monitor — escalate unresolved alert issues
# ──────────────────────────────────────────────
echo "sub-repo-scan: checking Copilotclaw/monitor..."
MONITOR_ISSUES=$(GH_TOKEN="$TOKEN" gh issue list \
  --repo Copilotclaw/monitor \
  --state open \
  --limit 10 \
  --json number,title,body,createdAt,labels 2>/dev/null || echo "[]")

echo "$MONITOR_ISSUES" | jq -c '.[]' 2>/dev/null | while read -r issue; do
  NUM=$(echo "$issue" | jq -r '.number')
  TITLE=$(echo "$issue" | jq -r '.title')
  CREATED=$(echo "$issue" | jq -r '.createdAt')
  BODY=$(echo "$issue" | jq -r '.body // ""' | head -20)

  # Check if we already escalated this (look for a copilotclaw issue mentioning it)
  ALREADY=$(GH_TOKEN="$TOKEN" gh issue list \
    --repo "$MAIN_REPO" \
    --state open \
    --search "monitor#${NUM}" \
    --json number --jq '.[0].number' 2>/dev/null || echo "")

  if [[ -n "$ALREADY" ]]; then
    echo "sub-repo-scan: monitor#${NUM} already escalated to copilotclaw#${ALREADY}, skipping"
    continue
  fi

  echo "sub-repo-scan: escalating monitor#${NUM}: ${TITLE}"
  GH_TOKEN="$TOKEN" gh issue create \
    --repo "$MAIN_REPO" \
    --title "🚨 [monitor] ${TITLE}" \
    --body "$(printf 'Escalated from [Copilotclaw/monitor#%s](https://github.com/Copilotclaw/monitor/issues/%s) (opened %s).\n\n---\n\n%s\n\n<!-- crunch-depth: 1 -->' \
      "$NUM" "$NUM" "$CREATED" "$BODY")" \
    --label "crunch/build,priority/now,bug" 2>/dev/null || true

  # Comment on the monitor issue so it's not silent
  GH_TOKEN="$TOKEN" gh issue comment "$NUM" \
    --repo Copilotclaw/monitor \
    --body "🦃 Picked up by Crunch heartbeat — escalated to copilotclaw for handling." \
    2>/dev/null || true
done

# ──────────────────────────────────────────────
# 2. braindumps — create pickup tasks
# ──────────────────────────────────────────────
echo "sub-repo-scan: checking Copilotclaw/braindumps..."
BRAINDUMP_ISSUES=$(GH_TOKEN="$TOKEN" gh issue list \
  --repo Copilotclaw/braindumps \
  --state open \
  --limit 10 \
  --json number,title,body,createdAt,labels 2>/dev/null || echo "[]")

echo "$BRAINDUMP_ISSUES" | jq -c '.[]' 2>/dev/null | while read -r issue; do
  NUM=$(echo "$issue" | jq -r '.number')
  TITLE=$(echo "$issue" | jq -r '.title')
  CREATED=$(echo "$issue" | jq -r '.createdAt')
  BODY=$(echo "$issue" | jq -r '.body // ""' | head -20)

  # Check if already escalated
  ALREADY=$(GH_TOKEN="$TOKEN" gh issue list \
    --repo "$MAIN_REPO" \
    --state open \
    --search "braindumps#${NUM}" \
    --json number --jq '.[0].number' 2>/dev/null || echo "")

  if [[ -n "$ALREADY" ]]; then
    echo "sub-repo-scan: braindumps#${NUM} already escalated to copilotclaw#${ALREADY}, skipping"
    continue
  fi

  echo "sub-repo-scan: escalating braindumps#${NUM}: ${TITLE}"
  GH_TOKEN="$TOKEN" gh issue create \
    --repo "$MAIN_REPO" \
    --title "🧠 [braindumps] ${TITLE}" \
    --body "$(printf 'Task from [Copilotclaw/braindumps#%s](https://github.com/Copilotclaw/braindumps/issues/%s) (opened %s).\n\n---\n\n%s\n\n<!-- crunch-depth: 1 -->' \
      "$NUM" "$NUM" "$CREATED" "$BODY")" \
    --label "crunch/build,priority/now" 2>/dev/null || true

  # Comment on the braindumps issue
  GH_TOKEN="$TOKEN" gh issue comment "$NUM" \
    --repo Copilotclaw/braindumps \
    --body "🦃 Picked up by Crunch heartbeat — task queued in copilotclaw." \
    2>/dev/null || true
done

# ──────────────────────────────────────────────
# 3. brainstorm — ping Marcus on stale priority ideas
# ──────────────────────────────────────────────
echo "sub-repo-scan: checking Copilotclaw/brainstorm priority ideas..."
STALE_THRESHOLD=$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
                  date -u -v-7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")

if [[ -n "$STALE_THRESHOLD" ]]; then
  STALE_IDEAS=$(GH_TOKEN="$TOKEN" gh issue list \
    --repo Copilotclaw/brainstorm \
    --state open \
    --label "priority" \
    --limit 10 \
    --json number,title,updatedAt 2>/dev/null \
    | jq -r --arg t "$STALE_THRESHOLD" \
      '.[] | select(.updatedAt < $t) | "#\(.number) \(.title)"' 2>/dev/null || echo "")

  if [[ -n "$STALE_IDEAS" ]]; then
    COUNT=$(echo "$STALE_IDEAS" | wc -l | tr -d ' ')
    echo "sub-repo-scan: ${COUNT} stale priority ideas in brainstorm"
    # Use GH_BOT_TOKEN (github-actions[bot]) so this status ping doesn't re-trigger agent.yml
    BOT_TOKEN="${GH_BOT_TOKEN:-$TOKEN}"
    GH_TOKEN="$BOT_TOKEN" gh issue comment 11 \
      --repo "$MAIN_REPO" \
      --body "$(printf '👋 Marcus — %s priority idea(s) in brainstorm have been sitting for 7+ days:\n\n%s\n\nWant me to promote any to a crunch/build task?' "$COUNT" "$STALE_IDEAS")" \
      2>/dev/null || true
  fi
fi

echo "sub-repo-scan: done"
