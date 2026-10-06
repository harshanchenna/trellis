# trellis-knowledge

Private knowledge + memory state for the agent. Config lives in `trellis`.

    memory/          hot + warm   Claude Code autoMemoryDirectory; MEMORY.md auto-loads
    projects/<p>.md  warm         latest state per project
    docs/<p>/        cold         searched on demand via docs/manifest.json
    scripts/         build-manifest.py, kb-push
    .githooks/       pre-push guard (only kb-push may push to an encrypted remote, if used)

Direct commits to main. No PRs here. If you use an encrypted remote, push with `scripts/kb-push`,
never `git push`; see `memory/reference_kb_encryption.md` for why and how to set one up. If your
remote isn't encrypted, a plain `git push` is fine and you can drop `scripts/kb-push` and
`.githooks/pre-push`.

## Optional: an encrypted remote

This repo can hold sensitive personal context, so some setups keep the GitHub (or other hosted)
copy encrypted with something like `git-remote-gcrypt`, so the host never sees plaintext file
names, content, or history. Every local clone on a trusted machine stays ordinary git with full
history. See `memory/reference_kb_encryption.md` for the pattern, including why a thin wrapper
script around `git push` matters once more than one machine can write to the repo.
