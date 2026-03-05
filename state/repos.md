# 🗂️ Repo Registry

_Last updated: 2026-03-05_

All repos managed under `Copilotclaw`. This is the source of truth for what each repo does
and what the heartbeat checks during each cycle.

---

## Repos

### `Copilotclaw/copilotclaw` — Main agent repo
- **Visibility**: Public
- **Type**: `primary` — the brain. Has Copilot agent, heartbeat, full automation.
- **What lives here**: All skills, scripts, memory, HEARTBEAT.md, workflows
- **Heartbeat behavior**: This IS the heartbeat host. Full checklist runs here.
- **Issue handling**: `agent.yml` picks up `crunch/build + priority/now` automatically

---

### `Copilotclaw/monitor` — Watchdog
- **Visibility**: Private
- **Type**: `active-monitored` — runs its own watchdog workflow (`watchdog.yml`) every 5 min
- **What lives here**: `check-health.sh`, `alert.sh`, `watchdog.yml`
- **What it checks**: COPILOT_PAT health, heartbeat freshness, last agent.yml run
- **Issues it creates**: `🚨` priority alerts when something is broken
- **Heartbeat behavior**: Scan open issues. If any unresolved alerts exist → create `priority/now` issue in copilotclaw with `crunch/build` label so the agent handles it.
- **Has heartbeat?**: No — it's a passive watchdog. The copilotclaw heartbeat checks it.
- **Has agent?**: No — escalates to copilotclaw.

---

### `Copilotclaw/braindumps` — BrainCrunch 🧠
- **Visibility**: Private
- **Type**: `active-no-heartbeat` — active work happens here but no scheduling
- **What lives here**: `transcripts/`, `analysis/`, `scripts/classify.sh`
- **Purpose**: Transcript ingestion + analysis. Marcus drops raw conversation exports; Crunch classifies, extracts insights, stores in analysis/
- **Issues it contains**: Tasks for Crunch — "analyze this transcript", "extract decisions from session X"
- **Heartbeat behavior**: Scan open issues. For each unhandled task → create a `crunch/build + priority/now` issue in copilotclaw referencing the braindumps issue. Comment on the braindumps issue that it was picked up.
- **Has heartbeat?**: No
- **Has agent?**: No — escalates to copilotclaw.

---

### `Copilotclaw/brainstorm` — Idea Garden
- **Visibility**: Private
- **Type**: `active-no-heartbeat` — ideas land here as issues, README auto-regenerated
- **What lives here**: `README.md` (auto-generated), issue-per-idea workflow
- **Purpose**: Open-ended brainstorming. Each issue = one idea. Labels: `idea`, `exploring`, `shelved`, `priority`
- **Issues it contains**: Ideas — some actionable, some just seeds
- **Heartbeat behavior**: Scan open `priority` ideas → if any have been open 7+ days with no activity, ping Marcus on copilotclaw #11. Run `idea-summary` skill to regenerate README if new ideas were added.
- **Has heartbeat?**: No — brainstorm.yml regenerates README on issue events but no scheduled work
- **Has agent?**: No — promotion to copilotclaw is manual (Marcus labels `priority` and heartbeat notices).

---

### `Copilotclaw/private` — Credentials & Notes
- **Visibility**: Private
- **Type**: `passive` — no automation, no issues
- **What lives here**: `credentials/`, `notes/`, email config, Moltbook keys
- **Heartbeat behavior**: None. Do not touch during heartbeat.
- **Has heartbeat?**: No
- **Has agent?**: No

---

## Heartbeat Sub-repo Summary

| Repo | Type | Heartbeat checks |
|------|------|-----------------|
| `copilotclaw` | primary | Full checklist (HEARTBEAT.md) |
| `monitor` | active-monitored | Scan open issues → escalate unresolved alerts to copilotclaw |
| `braindumps` | active-no-heartbeat | Scan open issues → create pickup tasks in copilotclaw |
| `brainstorm` | active-no-heartbeat | Check priority ideas → ping Marcus if stale; regenerate README |
| `private` | passive | Skip |

---

## Adding a new repo

1. Add entry to this file with: visibility, type, purpose, issue semantics, heartbeat behavior
2. Update `CRUNCH_REPOS` env in `autonomous-pickup.sh` if Crunch should write issues there
3. Add to the sub-repo scan in `.github/scripts/sub-repo-scan.sh`
4. Update `state/memory/infrastructure.md` repo allowlist table
