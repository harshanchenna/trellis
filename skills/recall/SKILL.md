---
name: recall
description: Retrieve past work, decisions, research, or project context from trellis-knowledge. Use when the user references prior sessions ("what did we decide about…", "recall…", "pull up the … doc") or when a task builds on earlier work.
argument-hint: "<topic>"
allowed-tools: Skill(update-state *), Read, Glob, Grep, Bash, Agent
---

# /recall

Walk the tiers from warm to cold and stop as soon as the question is answered. Everything is under `~/projects/trellis-knowledge/`.

1. **Hot** — `memory/MEMORY.md` is already in context. If an index line matches, read that memory file.
2. **Warm** — pick the project the topic belongs to and read `projects/<p>.md`. Its *Current state*, *Open threads*, and *Key decisions and cold docs* sections usually answer the question or name the exact cold doc.
3. **Cold, indexed** — search `docs/manifest.json` (entries have `path`, `title`, `type`, `topic`, `date`, `domain`, `headings`, `keywords`; `domain` is the project):
   ```bash
   python3 - "$TOPIC" <<'PY'
   import json, sys
   terms = sys.argv[1].lower().split()
   m = json.load(open('~/projects/trellis-knowledge/docs/manifest.json'))
   entries = m['entries']
   def score(e):
       hay = ' '.join([e.get('title',''), e.get('topic',''), e.get('path',''), ' '.join(e.get('keywords',[])), ' '.join(e.get('headings',[]))]).lower()
       return sum(hay.count(t) for t in terms)
   for e in sorted(entries, key=score, reverse=True)[:8]:
       if score(e): print(score(e), e.get('date',''), e['path'], '|', e.get('title',''))
   PY
   ```
   Read the top 1-3. Prefer newer docs and `synthesis` / `decision` types over raw stage notes and daily reports.
4. **Cold, grep** — only if the manifest finds nothing: `grep -ril "<keyword>" ~/projects/trellis-knowledge/docs/<p>/`.
5. **GitHub** — for code and project history: `gh issue list` / `gh pr list -R <your-github-user>/<repo> --search "<topic>" --state all`.

Dispatch a `general-purpose` subagent instead of reading inline when the recall spans two or more topics, needs synthesis over many docs, or main context is already heavy. Don't use `Explore` here: it reads excerpts, and synthesis needs whole docs. Tell it the job is read-only: read files and run grep only, and no connected tools and no writes. It sees none of your memory, so give it the topic, the project(s), the question to answer, and the route. The route: read `~/projects/trellis-knowledge/projects/<p>.md` first. Then read `docs/manifest.json`; its entries have `path` (relative to `docs/`), `title`, `type`, `date`, `domain`, and `keywords`, so match on those and read the top 1-3. Grep `docs/` only as a fallback. Ask it to return at most ~800 tokens: key findings first, then details with doc paths and dates, then gaps (where it looked and found nothing).

## Answering

- Lead with the answer, then cite doc paths and their dates.
- Recalled knowledge is what was true when written. If it names a file, host, price, position, or status, say how old it is, and verify against the live system before acting on it.
- If recall surfaces something that contradicts a project doc, fix the project doc (`/update-state`).
- Nothing found → say so and say where you looked. Don't reconstruct from guesswork.
