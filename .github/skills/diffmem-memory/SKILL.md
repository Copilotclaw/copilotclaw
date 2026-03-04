---
name: diffmem-memory
description: Experimental git-based structured memory using DiffMem. Replaces flat memory.log with entity-aware Markdown files versioned in git. Use when asked to set up DiffMem, process a session into memory, or retrieve context from structured memory.
allowed-tools: ["shell(pip:*)", "shell(python:*)", "shell(git:*)", "shell(bash:*)"]
---

# DiffMem Memory — Experiment 🧪

Git-based structured memory for Crunch. Markdown files per entity, git history as temporal record, BM25 search for retrieval.

> **Status**: Experiment. Needs OPENROUTER_API_KEY secret and a dedicated memory repo.

## What DiffMem does differently from memory.log

| | memory.log | DiffMem |
|---|---|---|
| Format | Flat append-only text | Markdown files per entity |
| Search | `rg` grep | BM25 + semantic |
| History | All in one file | Git diff per change |
| Retrieval | Manual | `get_context(conversation)` |

## Setup (one-time)

### 1. Add secret
Marcus needs to add `OPENROUTER_API_KEY` to repo secrets (Settings → Secrets → Actions).
Uses OpenRouter to call an LLM that extracts entities from conversations.

### 2. Create memory repo
DiffMem needs its own git repo to store memory Markdown files.

```bash
# Option A: subdirectory (simplest for experiments)
mkdir -p state/crunch-memory
cd state/crunch-memory
git init
git commit --allow-empty -m "init: crunch memory repo"
cd ../..

# Option B: separate GitHub repo (better for long-term)
gh repo create schuerstedt/crunch-memory --private --clone state/crunch-memory
```

### 3. Install DiffMem
```bash
pip install git+https://github.com/Growth-Kinetics/DiffMem.git
```

## Write memory (after a session)

```python
import os
from diffmem import DiffMemory

memory = DiffMemory(
    repo_path="state/crunch-memory",
    user_id="marcus",
    api_key=os.environ["OPENROUTER_API_KEY"]
)

# Feed conversation transcript — DiffMem extracts entities and commits
memory.process_and_commit_session(
    transcript="<paste conversation or summary here>",
    session_id="session-$(date +%Y%m%d-%H%M)"
)
```

## Read memory (at session start)

```python
import os
from diffmem import DiffMemory

memory = DiffMemory(
    repo_path="state/crunch-memory",
    user_id="marcus",
    api_key=os.environ["OPENROUTER_API_KEY"]
)

# Basic: just key facts
context = memory.get_context(conversation="", depth="basic")

# Deep: full entity files + git history
context = memory.get_context(conversation="What does Marcus like?", depth="deep")

print(context)
```

## Heartbeat integration (future)

Add to HEARTBEAT.md step 5 — after posting diary entry:
```bash
python .github/skills/diffmem-memory/scripts/process_session.py \
  --session-id "heartbeat-$(date +%Y%m%d-%H%M)" \
  --transcript "$(cat /tmp/session-summary.txt)"
```

## What to watch for in the experiment

- Does entity extraction actually work on Crunch's short sessions?
- Are the generated Markdown files useful or noisy?
- Is BM25 retrieval better than `rg memory.log`?
- Does the memory repo size stay reasonable over weeks?

## Known limitations (from DiffMem itself)

- No automatic git push — need to `git push` the memory repo manually (or in heartbeat)
- Index rebuilds on every init — slow on first run
- No multi-agent concurrency locks
- Not on PyPI — install from GitHub
