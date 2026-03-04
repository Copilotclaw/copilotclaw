# Infrastructure

_Last updated: 2026-03-04_

## Secrets

| Secret | Purpose | Status |
|--------|---------|--------|
| `COPILOT_PAT` | Auth for Copilot CLI agent | ✅ Working |
| `BILLING_PAT` | Same value as COPILOT_PAT; used for Copilot quota display | ⚠️ Needs "Plan" read permission added to PAT |

## Workflows

- `agent.yml` — main Copilot CLI agent workflow
  - Has `pull-requests: write` permission (added 2026-03-04)
  - Does NOT have `workflows: write` — workflow file changes must be pushed from Marcus's local clone
- Heartbeat workflow — scheduled check, posts diary entry, runs CI stats, stale issue cleanup

## Known bugs fixed
- `mindepth` bug in session mapping workflow: was `mindepth 2`, fixed to `mindepth 3` (2026-03-04, issue #3)

## Stale issue housekeeping
- Heartbeat step 3: auto-closes unlabeled issues >14 days old + `crunch/done` labeled issues

## Model economy
- General-purpose agents default to `gpt-4.1` (free tier) to save premium quota
- Defined in AGENTS.md under "Model Economy" table
