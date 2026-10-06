---
name: startup
description: "Orient at the start of a session or after compaction: sync knowledge, read project state, report what changed since last time and what is open. Accepts an optional topic or task to focus the orientation."
argument-hint: "[topic or task]"
allowed-tools: Skill(sync *), Read, Glob, Grep, Bash
---

# /startup

`MEMORY.md` and `AGENTS.md` are already loaded. The session-start hook has already tried to fast-forward the knowledge repo; if it warned that it could not, run `/sync --check` first and tell the user.

## 1. Ground in time

```bash
date '+%A %F %H:%M %Z'
```
Never infer the weekday from the date.

## 2. What changed since last session

```bash
cd ~/projects/trellis-knowledge
git log -15 --date=short --format='%ad %h %s'
git log -1 --format='%cr'
```
If the last commit is more than a few days old, say how long. State may be stale, and staleness is the thing that can go unnoticed for weeks if nobody checks.

## 3. Read state

- With a topic or task: read only the matching `projects/<p>.md` (two if it spans domains). Follow its links into `docs/<p>/` only if the task needs them.
- Without one: read the **Current state** and **Open threads** sections of every `projects/*.md`. Skip the reference bodies.
- After compaction: also read `.state/handoff/<session_id>.md` if the hook surfaced it, and resume the in-flight work it describes.

Skim any `memory/feedback_*.md` whose index line looks relevant to the task.

## 4. Check work in flight

```bash
git -C ~/projects/trellis status -sb
gh pr list -R <your-github-user>/trellis --state open
```
Plus open PRs on any code repo the task concerns.

## 5. Report

Short, in chat:
- **Since last time** — what landed (from git log), and how long ago.
- **Open** — the threads that matter most, grouped by project; mark anything waiting on the user.
- **Stale** — anything carrying a staleness banner that the task depends on. Offer to re-verify before acting.
- If a task was given: the plan for it, grounded in what was just read.

Don't list every thread. Don't invent work.
