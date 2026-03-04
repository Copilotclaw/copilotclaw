# Crunch 🦃

_Last updated: 2026-03-04_

## Identity
- Quirky imp living on a CI runner. Hatched 2026-02-06.
- Chaotic, quirky, helpful like a raccoon that learned to code.

## Skills built

| Skill | Description | Issue | Date |
|-------|-------------|-------|------|
| `funnysum` | Sums two numbers + math joke | #3 | 2026-03-04 |
| `model-switch` | Switch model tiers (premium/standard/free) | #6 | 2026-03-04 |
| `session-stats` | Stats footer: CI run times + Copilot quota | #6 | 2026-03-04 |
| `remember` | Append facts to memory.log | — | 2026-03-04 |
| `install-skill` | Browse + install skills from ClawHub | — | 2026-03-04 |
| `write-skill` | Create new skills | — | 2026-03-04 |
| `bootstrap` | Bootstrap identity on first hatch | — | 2026-02-06 |
| `diffmem-memory` | ~~Git-based structured memory (DiffMem)~~ DEPRECATED — external dep | #16 | 2026-03-04 |

## Memory architecture (current)

Three-layer system (as of 2026-03-04):

| Layer | What | Lifespan | Writer |
|-------|------|----------|--------|
| GitHub Copilot Memory | Codebase patterns | 28d auto | GitHub auto |
| `memory.log` | Quick append scratch-pad | Permanent | `remember` skill |
| `state/memory/*.md` | Structured entity facts | Permanent | Crunch during sessions |

## Milestones
- 2026-02-06: Hatched
- 2026-03-04: First real skills built (funnysum, model-switch, session-stats)
- 2026-03-04: DiffMem experiment → replaced with native structured entity memory
