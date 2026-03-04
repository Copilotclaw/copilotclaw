---
name: session-stats
description: Show model usage stats and CI run times. Auto-appended at end of every response as a stats footer. Also invoke explicitly when user asks about usage, cost, run times, or stats.
allowed-tools: ["shell(bash:*)", "shell(gh:*)"]
---

# Session Stats Footer

Append this footer to **every response** in the session. Keep it compact — one block at the bottom.

## Format

```
---
📊 **Session** | premium: N calls (models used) | free: N calls | 🏃 **Last CI runs**: ✅ 14:09 3m9s · ✅ 14:05 44s · ❌ 13:52 18s
```

## How to populate it

### Model usage (this session)
Track calls in the SQL session DB (`model_calls` table). Before each sub-agent call, insert a row. Then at response time, query counts:

```sql
SELECT tier, COUNT(*) as n, GROUP_CONCAT(DISTINCT model) as models
FROM model_calls GROUP BY tier;
```

If the table is empty (session just started), show `0 calls` for each tier.

### CI run times
Run the bundled script (last 5 runs, one-liner format):

```bash
bash .github/skills/session-stats/scripts/ci-stats.sh 3
```

Output example: `✅ 2026-03-04T14:09  3m 9s`

Condense to inline: `✅ 14:09 3m9s · ✅ 14:05 44s · ❌ 13:52 18s`

## Model tier reference

| Tier | Models |
|------|--------|
| free | `gpt-4.1`, `gpt-5-mini`, `gpt-5.1-codex-mini`, `claude-haiku-4.5` |
| standard | `claude-sonnet-4.5`, `gpt-5.1-codex`, `gpt-5.2-codex`, `gpt-5.3-codex` |
| premium | `claude-sonnet-4.6`, `claude-opus-4.5`, `claude-opus-4.6` |

## Tracking rule

Before every `task` tool call, insert into `model_calls`:
```sql
INSERT INTO model_calls (model, tier) VALUES ('gpt-4.1', 'free');
```

The *current session model* (me, Claude Sonnet 4.6) counts as **1 premium call per user message** — insert it on first tool use each turn.
