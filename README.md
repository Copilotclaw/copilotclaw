![copilotclaw banner](banner.jpeg)

A personal AI assistant that runs entirely through GitHub Issues and Actions. Like [OpenClaw](https://github.com/openclaw/openclaw), but no servers or extra infrastructure.

> **Origin**: This project started as a fork of [SawyerHood/gitclaw](https://github.com/SawyerHood/gitclaw) — even Crunch's name comes from there. It's since grown into its own thing.

Powered by [GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli). Every issue becomes a chat thread with an AI agent — but more than that, the agent can **write new skills for itself**, update its own instructions, and commit them back to the repo. Future sessions inherit everything it commits. The assistant evolves as you use it.

Conversation history is committed to git, giving the agent long-term memory across sessions. It maintains a `memory.log`, a user profile, and can grow its own capabilities over time.

---

> ⚠️ **Heads up for forks**: This project has grown beyond a simple chatbot. Today Crunch has:
> - **Its own GitHub org** (`Copilotclaw`) with full admin access
> - Ability to **create and manage repos** autonomously
> - Scheduled **heartbeat** that runs every 30 minutes, posts diary entries, and picks up work
> - **Autonomous task execution** — it can work issues without you prompting it
> - Connections to **Azure AI Foundry**, **Moltbook** (agent-only social network), and more
>
> Replicating this setup requires a dedicated GitHub account (or org), a GitHub Copilot subscription, multiple PAT scopes (`repo`, `issues`, `workflows`, `admin:org`), and an Azure AI Foundry deployment for LLM calls. It's a full agent infrastructure setup, not a quick fork-and-go.
>
> The basic "answer my issues" functionality still works with just a Copilot Requests PAT — but if you want the full system, budget a few hours for setup.

## How it works

1. **Create an issue** → the agent processes your request and replies as a comment.
2. **Comment on the issue** → the agent resumes the same session with full prior context.
3. **Everything is committed** → sessions, memory, and any file changes are pushed after every turn.
4. **The agent can extend itself** → it can write new skills, update `AGENTS.md`, and commit them so future sessions are smarter.

The agent reacts with 👀 while working and removes it when done.

### Repo as storage

All state lives in the repo:

```
AGENTS.md                   # agent identity + behavioral instructions (auto-loaded)
memory.log                  # append-only log of facts across all sessions
state/
  user.md                   # user profile (name, preferences)
  issues/
    1.json                  # maps issue #1 -> its Copilot CLI session ID
  copilot/
    sessions/
      <id>/                 # full session context for issue #1
.github/
  skills/
    bootstrap/SKILL.md      # first-run identity bootstrap
    write-skill/SKILL.md    # meta-skill: how to create new skills
    remember/SKILL.md       # how to write to memory.log
    <anything>/SKILL.md     # skills the agent writes for itself over time
```

Since everything is in git, it survives across ephemeral runners and is fully version-controlled.

## Setup

### Minimal setup (just the chatbot)

1. **Fork this repo**
2. **Create a fine-grained PAT** with **Copilot Requests** permission. (Requires an active GitHub Copilot subscription — available on all plans.)
3. **Add the PAT as a secret** named `COPILOT_PAT` in your fork's **Settings → Secrets and variables → Actions**.
4. **Hatch the agent** — open an issue titled anything (e.g. "Hello") and add the **`hatch`** label. The agent will introduce itself, ask about you, and write its own identity into the repo.
5. **Use it** — every subsequent issue is a task or conversation. The agent remembers everything across sessions.

### Full setup (autonomous agent with full account access)

For the heartbeat, autonomous pickup, Azure LLM calls, and self-evolving capabilities:

1. **Create a dedicated GitHub org or account** for the agent (so it has its own identity, separate from yours).
2. **Create a full-access PAT** with scopes: `repo`, `issues`, `workflows`, `admin:org`, `Copilot Requests`.
3. **Secrets required:**
   - `COPILOT_PAT` — full-access PAT (used by the agent for all GitHub operations)
   - `BILLING_PAT` — same value as `COPILOT_PAT`; used for Copilot quota display (needs "Plan" read permission added)
   - `AZURE_ENDPOINT` — Azure AI Foundry base URL
   - `AZURE_APIKEY` — Azure AI Foundry API key
4. **Enable GitHub Pages** on `main` branch (optional — for the live dashboard at `<org>.github.io/<repo>`).
5. Hatch the agent as above.

## Security

The workflow only responds to repository **owners, members, and collaborators**. Random users cannot trigger the agent on public repos.

If you plan to use copilotclaw for anything private, **make the repo private**. Public repos mean your conversation history is visible to everyone, but get generous GitHub Actions usage.

## Configuration

Everything lives in `.github/workflows/agent.yml` — no separate scripts. Common tweaks:

- **Model:** Add `--model MODEL` to the `copilot` invocation in the **Run agent** step (e.g. `--model claude-sonnet-4-5`).
- **Tools:** Restrict with `--available-tools read,grep,glob` for read-only analysis.
- **Reasoning:** Add `--experimental` and set `reasoning_effort` in `.copilot/settings.json`.
- **Trigger:** Adjust the `on:` block to filter by labels, assignees, etc.
- **AGENTS.md:** Already loaded automatically as custom instructions for the agent.

## Heartbeat

The agent runs on a **30-minute schedule** via `.github/workflows/heartbeat.yml`. Every 30 minutes it:

1. Reads recent memory and scans open `priority/now` issues
2. Checks CI health
3. Posts a diary entry to the pinned [🫀 Heartbeat Diary](../../issues/10) issue
4. Writes anything notable to `memory.log` and commits it

This makes the agent *proactive* — not just reactive to your comments. The `HEARTBEAT.md` file is its checklist.

### Roadmap

| Milestone | Status | What it unlocks |
|-----------|--------|-----------------|
| v0.1 — Heartbeat Alive | ✅ Done | Scheduled runs, diary, memory |
| v0.2 — Issue Spawning | ✅ Done | Crunch creates its own tasks |
| v0.3 — Autonomous Skills | ✅ Done | Crunch works `crunch/build` issues alone |
| v0.4 — Own GitHub Org | ✅ Done | Full account, private repos, multi-repo network |
| v0.5 — Email + Comms | 📬 Planned | Daily digest email to you |
| v0.6 — Multi-Crunch | 🔮 Planned | Specialized worker agents in separate repos |

## Acknowledgments

Forked from [gitclaw](https://github.com/SawyerHood/gitclaw) by [@SawyerHood](https://github.com/SawyerHood). Now living as [copilotclaw](https://github.com/Copilotclaw/copilotclaw) in its own GitHub org. Original project built on top of [pi-mono](https://github.com/badlogic/pi-mono) by [Mario Zechner](https://github.com/badlogic). Powered by [GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli).
