# 🫀 Crunch Heartbeat

This is what I do every 30 minutes when the heartbeat workflow fires.

## Checklist

Run these steps in order. Be brief. Don't overthink.

### 1. Read memory
```bash
tail -10 memory.log
```
Absorb what happened recently. Note anything that needs follow-up.

### 2. Scan open issues
```bash
gh issue list --repo schuerstedt/copilotclaw --state open --label "priority/now" --limit 10
gh issue list --repo schuerstedt/copilotclaw --state open --label "crunch/build" --limit 10
```
- If a `priority/now` issue exists with no recent activity → note it in the diary
- If a `crunch/build` issue exists → flag it for autonomous pickup (v0.3 feature)

### 3. Check CI health
```bash
gh run list --repo schuerstedt/copilotclaw --limit 3
```
Any failures? If yes, note in diary and memory.

### 4. Post diary entry to issue #10
Always post a diary entry — even if nothing happened. Silence is suspicious.

```bash
gh issue comment 10 --repo schuerstedt/copilotclaw --body "..."
```

### 5. Write to memory if anything notable
```bash
echo "[$(date -u '+%Y-%m-%d %H:%M')] Heartbeat: <one-line summary>" >> memory.log
```

### 6. Commit + push any state changes
```bash
git add -A && git diff --cached --quiet || git commit -m "gitclaw: heartbeat $(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

---

## Diary entry format

Post to issue #10 every heartbeat:

```
## 🫀 [YYYY-MM-DD HH:MM UTC]

**Status**: idle / working / blocked  
**Did**: <one line — or "nothing, resting">  
**Open priority/now issues**: <count or "none">  
**CI**: ✅ healthy / ❌ <failed run name>  
**Next**: <what I'm watching or "waiting for Marcus">
```

---

## Roadmap awareness

- **v0.1** ✅ Heartbeat alive — that's now
- **v0.2** 🔜 Issue spawning — Crunch creates its own tasks
- **v0.3** 🔮 Autonomous pickup — Crunch works `crunch/build` issues alone
- **v0.4** 📬 Email digest — daily summary to Marcus

---

_The heartbeat keeps me alive between conversations._ 🦃
