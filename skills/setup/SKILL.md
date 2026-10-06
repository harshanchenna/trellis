---
name: setup
description: "Guided first-run setup: interview what the agent is for, check prerequisites, create or clone the encrypted knowledge repo, wire memory/.env, optionally set up the scheduled-jobs repo, and verify each step. Use on a fresh machine or a fresh clone, when the user says 'set me up' or 'new machine', or as the first command after cloning this template."
argument-hint: "[--new-device] [--skip-cron]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# /setup

First-run setup for this agent, on a machine that has never run it before. Two people hit this
skill: someone who already has these repos on another machine (repos already exist, just need
cloning and the key importing), and anyone who cloned this as a template and is running it for the
first time (nothing exists yet, build it from scratch). Both paths share every step below; step 2
decides which branch a given step takes. Never print a secret value at any point in this skill - names
and presence only.

## 1. Interview

Ask before doing anything:

1. **What is this agent for?** The domains/projects it should track (work, home, research,
   whatever the user names) become the initial set of `projects/<p>.md` in the knowledge repo. Don't
   invent projects they didn't name.
2. **GitHub username** - `gh` should already be authenticated as this user (checked in step 3).
3. **Knowledge repo name** - default `<this-repo-name>-knowledge` (e.g. this repo is
   `trellis` -> `trellis-knowledge`), matching the naming this agent already uses for itself.
4. **Jobs/cron repo** - set up now, later, or skip? (`--skip-cron` skips without asking.)
5. **MCP servers / integrations** beyond native web search - names only, e.g. "a market data API",
   "my task tracker". This just decides what step 7 wires up; it doesn't write server configs for
   arbitrary services.

## 2. Detect returning vs. fresh

```bash
GH_EXISTS=false
gh repo view "<username>/<knowledge-repo-name>" >/dev/null 2>&1 && GH_EXISTS=true

if [ "$GH_EXISTS" = false ] && [ -d ~/projects/<knowledge-repo-name> ] \
   && [ -n "$(ls -A ~/projects/<knowledge-repo-name> 2>/dev/null)" ]; then
  echo "~/projects/<knowledge-repo-name> already exists locally and isn't empty, but there's no" \
       "GitHub repo by that name. Stopping - this doesn't match either the fresh or returning" \
       "path; find out what that directory is before setup touches it."
  exit 1
fi

[ "$GH_EXISTS" = true ] && echo returning || echo fresh
```

A populated local directory with no matching GitHub repo isn't "fresh" - scaffolding over it would
silently clobber whatever's already there. It also isn't "returning" in the normal sense (nothing to
clone from). Stop and ask rather than guessing.

**Returning** (repo already exists - this is almost always a second machine for the same user, if
you already have these repos elsewhere): clone what's there and import the existing key rather than
generating a new one. `--new-device` skips the detection round-trip when this is already known.

**Fresh**: nothing exists yet, scaffold everything from this step forward.

## 3. Prerequisites

```bash
for c in git gh uv gpg git-remote-gcrypt jq; do command -v "$c" >/dev/null || echo "missing: $c"; done
gh auth status >/dev/null 2>&1 || echo "gh not authenticated - run: gh auth login"
```

`uv` is optional if a working `python3` is already on the box - only flag it missing if neither is
present. For anything missing, print the install command for this platform (Debian/Ubuntu:
`sudo apt-get install -y git gh gnupg git-remote-gcrypt jq`; `uv` via its own installer script) and
stop. Don't proceed past a missing prerequisite or a `gh` that isn't authenticated - every later step
depends on both.

## 4. Knowledge repo

**Returning**: follow "New machine / new clone" in the knowledge repo's own
`memory/reference_kb_encryption.md` (its README points there too):

```bash
git clone -b main "gcrypt::https://github.com/<username>/<knowledge-repo-name>.git" ~/projects/<knowledge-repo-name>
cd ~/projects/<knowledge-repo-name>
git config core.hooksPath .githooks
git config remote.origin.gcrypt-participants <fingerprint>   # from the imported key, step 5
```

Import the key itself in step 5 before this clone will decrypt anything.

**Fresh**: scaffold the tier layout locally first, encrypt in step 5, then create and push.

```bash
mkdir -p ~/projects/<knowledge-repo-name>/{memory,projects,docs,scripts,.githooks}
cd ~/projects/<knowledge-repo-name> && git init -q
```

This repo ships a `templates/knowledge/` directory with the starting point for a fresh knowledge
repo: the tier layout, `scripts/build-manifest.py`, `scripts/kb-push`, `.githooks/pre-push`, and the
gcrypt reference guide. Copy its contents in wholesale and fill in the per-project stubs: a minimal
`memory/MEMORY.md` index, one `projects/<p>.md` stub per project named in step 1, and an empty
`docs/manifest.json` (`[]`). See `memory/reference_kb_encryption.md`'s "Why kb-push exists" for what
the push-lock guard is protecting against (a plain `git push` to an encrypted remote can silently
drop commits).

```bash
gh repo create "<username>/<knowledge-repo-name>" --private --description "Knowledge base for <agent name>"
```

## 5. gcrypt encryption

**Returning**: import the existing key from the password manager. Have the user paste the
`gpg --export-secret-keys --armor <fpr>` block directly into `gpg --import` (interactively, or from
a file they delete immediately after) - never through this chat, since that would put the key
material in the conversation transcript. Then set `gcrypt-participants` to that fingerprint (step 4).

**Fresh**: before generating anything, check whether a key for this exact uid already exists - a
retried or partial earlier run can leave one behind, and picking "the first secret key on the ring"
instead of this specific uid can silently reuse a stale, unrelated key:

```bash
UID_STR="<knowledge-repo-name> (gcrypt)"
EXISTING_FPR=$(gpg --with-colons --list-secret-keys "$UID_STR" 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')
```

If `$EXISTING_FPR` is non-empty, show it to the user (`Found an existing key for "$UID_STR":
$EXISTING_FPR`) and ask whether to reuse it or generate a new one. Reusing skips straight to setting
`FPR="$EXISTING_FPR"` below. Otherwise, generate a new passphrase-less key (no passphrase, so
unattended sessions and jobs can push and pull without a prompt), and look up its fingerprint by the
same exact uid, not by any key that happens to be on the ring:

```bash
gpg --batch --pinentry-mode loopback --passphrase '' --quick-gen-key "$UID_STR" default default never
FPR=$(gpg --with-colons --list-secret-keys "$UID_STR" | awk -F: '/^fpr:/{print $10; exit}')
git -C ~/projects/<knowledge-repo-name> remote add origin "gcrypt::https://github.com/<username>/<knowledge-repo-name>.git"
git -C ~/projects/<knowledge-repo-name> config core.hooksPath .githooks
git -C ~/projects/<knowledge-repo-name> config remote.origin.gcrypt-participants "$FPR"
```

The remote has to exist before `gcrypt-participants` is set - `git config` on a remote that isn't
there yet succeeds silently, and the first `kb-push` would otherwise fail with nothing to push to.

Then tell the user, verbatim, before doing anything else:

> Back this up now: `gpg --export-secret-keys --armor $FPR` - save the output in your password
> manager. If every copy of this key is ever lost, the GitHub copy of your knowledge base becomes
> unreadable (your local clones are unaffected). This session won't run that export for you or hold
> the output - run it yourself so the key material never has to pass through here. Example
> fingerprint format: `<your-gpg-key-fingerprint>`.

Push for the first time with the repo's own `kb-push` (from the template or scaffolded in step 4),
never a plain `git push` - see that script's comment for why a gcrypt remote needs it.

## 6. `.env`

```bash
[ -f .env ] || cp .env.example .env
while read -r key; do
  grep -q "^${key}=" .env || echo "${key}=" >> .env
done < <(grep -oE '^[A-Z0-9_]+=' .env.example | sed 's/=$//')
grep -oE '^[A-Z0-9_]+=' .env.example | sed 's/=$//'
```

`[ -f .env ] || cp` means a re-run never overwrites an `.env` that already has secrets pasted in -
plain `cp` would wipe it. The loop then adds only whatever keys are missing (new ones added to
`.env.example` since the last run), leaving existing values untouched. Tell the user which key
*names* need values and ask them to open `.env` and paste the values in themselves - never ask for a
secret in chat, and never `cat .env` to show them what they entered.

Verify presence only:

```bash
while read -r key; do
  grep -q "^${key}=." .env && echo "$key: set" || echo "$key: MISSING"
done < <(grep -oE '^[A-Z0-9_]+=' .env.example | sed 's/=$//')
```

## 7. Wire memory, directories, and MCP servers

Edit `.claude/settings.json`:
- `autoMemoryDirectory` -> `~/projects/<knowledge-repo-name>/memory`
- `permissions.additionalDirectories` -> the knowledge repo, and the jobs repo if step 8 ran
- `enabledMcpjsonServers` -> only if step 1 named integrations *and* this repo ships a matching
  `.mcp.json` template. Otherwise leave it empty and say so: MCP servers here are bring-your-own,
  point the user at Anthropic's MCP docs to add one, and note that everything else (research,
  recall, digests) works over native web search without any server at all.

## 8. Jobs/cron repo (optional - skip if declined in step 1, or with `--skip-cron`)

Same clone-or-create logic as step 4, without the encryption - scheduled-job definitions (schedule,
which skill, prompt, output location) aren't personal the way a knowledge base is. If that stops
being true for what this user is scheduling (a job whose prompt or output touches personal data),
say so and treat it like the knowledge repo instead. This repo ships a `templates/cron/` directory
with the starting point for a fresh jobs repo (job-file format, a runner, and a health check); copy
it in as the base, then wire whatever mechanism actually fires it on schedule (a systemd timer or a
crontab entry invoking `claude -p "<job prompt>"`), and register it per that template's own
instructions.

## 9. Verify

- `jq . .claude/settings.json >/dev/null` - settings file still parses
- `git -C ~/projects/<knowledge-repo-name> log -1` succeeds (proves the clone decrypts, or the fresh
  repo has at least one commit)
- `gpg --list-secret-keys "$FPR"` shows the key is actually in the local keyring
- every key from step 6 reports "set"
- a trial push through `kb-push` (or its fresh-repo equivalent) succeeds
- if MCP servers were wired: they show up without error (`claude mcp list` or the harness's
  equivalent)

Report what's done, what's still open (e.g. "paste these three .env values, then re-run step 6's
check"), and nothing that looks like a secret, even partially.
</content>
