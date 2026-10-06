# Memory index

Auto-loads every session (first 200 lines / 25KB). Everything it points to loads on demand.
Subagents get none of this.

## Knowledge map (this repo: ~/projects/trellis-knowledge)

- `memory/` — this index + native memory files. HOT index, WARM files.
- `projects/<p>.md` — WARM. Latest state per project. Read the matching one before working in a
  domain.
- `docs/<p>/` — COLD. Search via `docs/manifest.json`, grep as fallback. Rebuild:
  `python3 scripts/build-manifest.py`.
- Commits go straight to main here. No PRs on this repo.
- If you use an encrypted remote, push with `scripts/kb-push`, never `git push`. Key, clone, and
  recovery steps: [KB encryption](reference_kb_encryption.md).

## Projects

<!-- One line per project, pointing at projects/<p>.md. Example: -->
<!-- - [self-improve](../projects/self-improve.md) — the agent itself; refactor status; self-improve runs -->

## User

<!-- Pointers to user_profile.md, user_now.md, user_writing_voice.md, etc., once you've written them. -->

## Active threads

<!-- Short-lived threads worth surfacing every session; move to a project doc once they settle. -->

## Feedback (apply always)

<!-- One line per standing correction, pointing at a feedback_*.md file. Promoted here by /self-improve. -->

## Environment

<!-- Machine/host facts worth surfacing every session: OS, package managers, timezone quirks, known tool gotchas. -->
