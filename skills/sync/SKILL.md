---
name: sync
description: Bring the agent's three repos (trellis, trellis-knowledge, trellis-cron) in line with their remotes and report anything uncommitted, unpushed, or diverged. Use at the start of work on a different machine, after editing config elsewhere, or when the user says "sync".
argument-hint: "[--check]"
allowed-tools: Bash, Read
---

# /sync

For each of `~/projects/trellis`, `~/projects/trellis-knowledge`, `~/projects/trellis-cron`:

```bash
git -C <repo> fetch -q --prune
git -C <repo> status -sb
if git -C <repo> rev-parse --abbrev-ref @{u} >/dev/null 2>&1; then
  git -C <repo> rev-list --left-right --count @{u}...HEAD   # behind  ahead
else
  echo "no upstream (local-only branch)"
fi
```
A missing clone: `gh repo clone <your-github-user>/<name> ~/projects/<name>`, except trellis-knowledge, which may be encrypted on GitHub: follow "New machine / new clone" in its `memory/reference_kb_encryption.md` (or its README) if so.

With `--check`, report only. Otherwise act per repo:

**trellis-knowledge** (direct-to-main)
- Behind → `git pull --rebase --autostash`.
- Ahead → push via the repo's push script if it has one (e.g. for an encrypted remote), never `git push` directly in that case; see `/update-state` step 6.
- Uncommitted changes → don't commit them here. Say so and point to `/update-state`, which knows what the changes mean.
- Conflict → stop and show it.

**trellis, trellis-cron** (PR flow)
- On `main`, clean, behind → `git pull --ff-only`.
- On `main` with local commits or edits → don't push. Report it: config changes go through a branch and a PR.
- On a feature branch → report branch, ahead/behind, and whether a PR exists (`gh pr list --head <branch>`). Push the branch only if it already has an upstream.
- A pulled change to `.claude/settings.json`, `.mcp.json`, or `hooks/` takes effect next launch. Say so.

Also check: `.env` exists in `trellis` and has every key named in `.env.example` (report names of missing keys, never values).

## Report

One table: repo · branch · ahead/behind · dirty? · action taken. Then anything that needs the user.
