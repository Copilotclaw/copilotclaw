# Architecture & Design Decisions

_Last updated: 2026-03-04_

## Memory system

### 2026-03-04 — Replace DiffMem with native structured memory
- **Decision**: Drop DiffMem (external pip dep + OpenRouter API key required). Too fragile.
- **Alternative**: Entity Markdown files in `state/memory/` — no deps, git-tracked, I (Claude) do extraction.
- **Rationale**: Simpler, gitable, I AM the LLM. No secrets needed.
- **Files**: `marcus.md`, `crunch.md`, `infrastructure.md`, `decisions.md`

### 2026-03-04 — Three-layer memory architecture
- GitHub Copilot Memory (28d, auto) for codebase context
- `memory.log` as fast append scratch-pad (grep-friendly)
- `state/memory/*.md` as canonical structured entity store

## Agent model economy

### 2026-03-04 — Default sub-agents to free/cheap models
- **Decision**: `general-purpose` agents default to `gpt-4.1` (free), not Claude Sonnet.
- **Rationale**: Most sub-agent tasks don't need heavy reasoning. Save premium quota for actual hard stuff.

## Skill architecture

### 2026-03-04 — Skills as SKILL.md files in .github/skills/
- Each skill is a self-contained directory with a `SKILL.md` describing what it does and how.
- Skills are invoked by the `skill` tool with just the skill name.
- New skills committed here are available to all future sessions.
