# trellis-knowledge

What the agent knows. The agent's config and rules live in `trellis` (its `AGENTS.md` wins on
conflict). This repo is state, pure state.

## Layout (tiers)
- `memory/MEMORY.md`: **hot**. It auto-loads into every session, so it is an **index**: one line
  per entry, under ~150 lines and hard-capped at 200 lines / 25KB.
- `memory/*.md`: **warm**. One fact per file, with frontmatter `name`, `description`,
  `metadata.type` (user | feedback | project | reference). Anything learned from web or MCP
  content carries a `source:` line.
- `projects/<p>.md`: **warm**. Latest state per project. Sections: Purpose, Current state, Open
  threads, How I think about this domain, Key decisions and cold docs, Last updated. The latest
  state, not a log; keep each under ~30KB.
- `docs/<p>/`: **cold**. Long-form docs, named `YYYYMMDDTHHMMZ_<type>-<slug>.md` with frontmatter
  `type` / `topic` / `date`. Found through `docs/manifest.json` (rebuild it with
  `python3 scripts/build-manifest.py` after adding docs). Never bulk-load.
- `alerts.md`: the open items that need the user, one section per source (`## Work`,
  `## Email`, `## Cron`, ...).
- `scripts/`: `build-manifest.py`, `kb-push`. `.githooks/`: the pre-push guard.

## Rules
- **Commits go straight to main. No PRs, never reviewed.** Messages look like
  `<project>: <what changed>`, with no AI-attribution lines.
- **Stage only the paths you changed.** Never `git add -A`: other sessions may write here at the
  same time, and a path you didn't touch is someone's work in progress.
- **Push only with `scripts/kb-push`**, never `git push` (if you use an encrypted remote; see
  `memory/reference_kb_encryption.md`). A plain remote doesn't need this.
- **Living logs**: `alerts.md` and any weekly rollups. The rule itself (current state only, git
  history is the log, keep only the latest N weekly docs on disk) is defined in trellis's
  `AGENTS.md`, under Knowledge tiers; follow it there. Project docs and memory are not logs.
- **Update before creating.** New knowledge goes into an existing project unless the user names a
  new one; update a living doc before creating a sibling.
- **Memory is a hypothesis.** It records what was true when written. Delete memories proven
  wrong, and fix a project doc the moment you find it stale.
- **Secrets never go here**, not even encrypted. They live in `trellis/.env`.
- Keep this file and `README.md` current when the layout or rules change.
