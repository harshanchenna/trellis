---
name: reference-kb-encryption
description: "Optional pattern: keep the hosted copy of trellis-knowledge encrypted with git-remote-gcrypt; push only via scripts/kb-push; key, clone, and recovery steps"
metadata:
  node_type: memory
  type: reference
---

**What:** This repo can hold sensitive personal context, so some setups keep the hosted copy
(GitHub or elsewhere) encrypted with `git-remote-gcrypt` — the host sees only opaque blobs, no
file names, no history. Clones on trusted machines are ordinary git with full history, so
`git log`, blame, and grep all work as usual. Skip this whole pattern if your knowledge repo has
nothing sensitive in it, or if your host already satisfies your privacy bar on its own.

**Daily use (if you adopt this):**
- Commit as usual. **Push only with `~/projects/trellis-knowledge/scripts/kb-push`**, never
  `git push`. It takes a machine-wide lock and fetches. If the remote has commits from another
  machine, it rebases onto them (autostashing the working tree, other sessions' edits included).
  Then it pushes.
- `.githooks/pre-push` (enabled by `git config core.hooksPath .githooks`) refuses any push to a
  `gcrypt::` remote that doesn't come through kb-push.
- Pull as usual (`git pull --rebase`). It decrypts on the fly.

**Why a push wrapper matters:** gcrypt can accept a push that is missing the remote's newer
commits and **silently drop them**. Plain git would reject it. Don't "fix" this with a pre-push
hook that fetches: a fetch in the middle of gcrypt's push can corrupt the remote.

**Key:** a GPG key dedicated to this repo, with no passphrase so sessions and jobs can run
unattended. It lives in the local GPG keyring on each trusted machine. Keep an offline backup of
the exported secret key (`gpg --export-secret-keys --armor <fingerprint>`) somewhere durable,
such as a password manager. If every copy of the key is lost, the hosted copy can't be read;
local clones are unaffected. In that case, generate a new key and re-push from a clone.

**New machine / new clone:**
1. Install `git-remote-gcrypt`, then import the key (`gpg --import`, paste the block).
2. Clone and configure:
   ```
   git clone -b main gcrypt::https://github.com/<your-github-user>/trellis-knowledge.git ~/projects/trellis-knowledge
   cd ~/projects/trellis-knowledge
   git config core.hooksPath .githooks
   git config remote.origin.gcrypt-participants <your-gpg-key-fingerprint>
   ```
3. Check it with `git log -1`.

**Maintenance:**
- Another key (a second machine with its own key): add its fingerprint to `gcrypt-participants`
  (space-separated), then kb-push. Only new pushes are readable by the new key.
- Rotating the key: new key → set participants → kb-push → remove the old key.
- If a push is refused: run `git pull --rebase origin main`, resolve any conflict, then kb-push
  again.

**What it costs:** you lose the host's web browsing and diffing of the knowledge base. Anything
that needs to read this repo without the key (a cloud job, an off-box check) can't — plan for
that separately if you need it.
