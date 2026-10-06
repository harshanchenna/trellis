# trellis-cron

Scheduled work for the agent (`trellis`). This repo holds the job definitions, the runner, the
alert helper, the liveness check, and the systemd `--user` units that fire them. It owns
*schedule*, *which skill*, *prompt*, and *tool allowlist* for each job — the skills themselves
live in `trellis/skills/`.

## Layout

    jobs/<name>.job     bash-sourceable job definition: SCHEDULE, KIND, PROJECT, TIMEOUT_MIN,
                        DESCRIPTION, SUCCESS, and (claude kind) PROMPT + optional ALLOWED_TOOLS /
                        DISALLOWED_TOOLS override + PERMISSION_MODE, or (script kind) SCRIPT
    bin/run-job         runs one job by name: lock, log, last.json, prune old logs
    bin/ping            DMs an alert to the user on Discord via a bot (DISCORD_BOT_TOKEN +
                        DISCORD_ALERT_USER_ID from trellis's .env)
    bin/cron-health     deterministic liveness check across all jobs (not Claude); a scheduled job
    bin/install         generates/enables/removes the systemd --user units from jobs/*.job
    scripts/            plain scripts run by `script`-kind jobs, if any

Job state (logs, `last.json`) lives outside the repo at `~/.local/state/trellis-cron/<name>/`.
Generated systemd units land in `~/.config/systemd/user/trellis-cron-<name>.{service,timer}`.

## The `.job` file format

Required in every job: `SCHEDULE` (a systemd `OnCalendar` expression, local wall-clock, no
timezone suffix — `bin/install` and `bin/cron-health` both append your configured timezone),
`KIND` (`claude` or `script`), `PROJECT`, `TIMEOUT_MIN`, `DESCRIPTION`, `SUCCESS` (`exit0`, or
`kb-commit:<pathspec>` — a trellis-knowledge commit touching that path since the run started).

`claude` kind additionally needs `PROMPT` (the slash command to run, e.g. `/dream` or
`/cron-health --dry-run`). `script` kind needs `SCRIPT` (a command run from the repo root
under `bash -o pipefail -c`, e.g. `scripts/foo.sh` or `python3 scripts/foo.py`).

**Tool allowlists have one source of truth: the skill's own `SKILL.md` frontmatter.** For a
`claude`-kind job, `run-job` derives the skill name from `PROMPT` (the leading `/` and anything
from the first space on stripped — `/dream --flag` names the `dream` skill) and reads
`allowed-tools` from `~/projects/trellis/skills/<skill>/SKILL.md`'s frontmatter. A `.job` file
does *not* copy that list — copies drift. A job may set its own `ALLOWED_TOOLS` to deliberately
override the skill's list, but that should be rare and commented. If the skill file doesn't
exist yet, or has no `allowed-tools` key, and the job sets no override, the run fails closed
(non-zero exit, recorded in `last.json`) rather than running with an empty or wrong tool surface.

A job may also set `DISALLOWED_TOOLS` (space- or comma-separated, passed to
`claude -p --disallowedTools`; deny rules beat allow rules). `run-job` always prepends
`Bash(sudo:*)` to it — no job ever gets `sudo`, regardless of what's on its allowlist. Use
`DISALLOWED_TOOLS` for a mechanical backstop to a skill's hard rule that's worth enforcing twice —
for example, a job that must never push or touch a remote when run unattended.

Every `claude`-kind run also passes `--permission-prompts none`: there's no one to answer a
prompt in a headless run, so anything not resolved by the allow/deny lists and permission mode
is refused outright instead of hanging until the timeout.

Every `claude`-kind run also gets one fixed `--append-system-prompt` note from `run-job`: run a
skill's commands exactly as written, one per Bash call. Commands the model composes itself are
one plain command (a pipe only when every part is allowlisted), with no `cd`, chains, loops or
appended `echo`, and it uses Glob/Read instead of shell loops. Under an allowlist, a compound
command is refused whole even when each part is allowed. This is the one place `run-job` speaks
to *how* a run uses its tools. Skills still own the procedure, and their frontmatter is still the
only source of the tool list. A compound command a skill writes itself (e.g. `git fetch && git
status`) is fine as long as every part is on its allowlist.

`PERMISSION_MODE` is optional and defaults to `auto`. **A job that ingests untrusted external
content (email bodies, web pages, third-party API payloads) sets `PERMISSION_MODE=dontAsk`.** In
`dontAsk`, anything not on the allowlist is refused outright instead of prompted — since there's
no one to answer a prompt in a headless run, `auto` would otherwise let untrusted content reach a
wider tool surface than intended. When a skill legitimately needs to act on untrusted input, add
that action to the skill's own allowlist deliberately and narrowly; don't widen by switching back
to `auto`.

## Rules

- **Keep `README.md` current** as your go-to reference whenever a job is added, removed, or
  changed — schedule table, health/rerun instructions, add/remove-a-job steps.
- **Delegation principle**: jobs are silent by default. They fix what's within their latitude,
  record it, and commit. They ping the user (`bin/ping`) only when something is blocked on them
  or is critical — a normal day produces no ping. A ping that matters gets recorded with
  `bin/ping ... --record <Section>`, which appends a dated line under `## <Section>` in
  `trellis-knowledge/alerts.md` and commits/pushes just that file. `cron-health` manages its own
  `## Cron` section separately (open failures only, resolved ones removed automatically — that
  one's a live status, not an append-only log).
- **Message sources for `bin/ping`**: `--file PATH` or `-` (stdin) for anything derived from
  outside the job's own script — email content, web pages, API responses. Plain argv is only for
  a short trusted literal a script builds itself (a status line, not user- or API-controlled
  text) — argv gets shell-expanded, and untrusted content has no business on a command line.
- **Never `--bare`, never an API key.** These jobs run as `claude -p` under a Claude Code
  subscription. `bin/run-job` refuses to start if `ANTHROPIC_API_KEY` or `ANTHROPIC_AUTH_TOKEN`
  is set, because that would silently bill the API instead.
- **No job ever gets `sudo`.** `run-job` denies `Bash(sudo:*)` for every `claude`-kind job by
  default (see `DISALLOWED_TOOLS` above); no job's allowlist should include it either.
- **Pick a schedule and stay out of your host's DST transition window**, if it observes one,
  when choosing or changing a `SCHEDULE`.
- **No secrets in files, and no secrets on a command line.** Anything sensitive (bot tokens, API
  keys, service credentials) lives in a gitignored `.env`, read at the point of use — never a
  hardcoded default, a doc, or a commit. `bin/ping` is the reference pattern: read only the
  key(s) needed, never `source` the file, never echo the value, and read the token inside python
  rather than argv, so it never shows up in `ps`. `run-job`, `bin/ping`, and `bin/cron-health` all
  set `umask 077` — job state and logs are not world-readable.
- Every `script`-kind job that talks to the outside world reports failure through `bin/ping`, not
  its own bespoke notification path — except a very high-frequency job, where a ping per failed
  run would be noisy; rely on `cron-health`'s sweep to surface a stalled or failing run instead.

## PR flow

Branch → PR → `/code-review` → merge, per `trellis`'s Merging lanes (this repo shares them):
config/hotfix changes are fast-lane; changes to `jobs/`, `bin/`, or this file are reviewed lane;
anything widening access (a new allowed tool pattern, a switch away from `dontAsk`, enabling a
timer) needs the user's own say. `/code-review` runs on every non-fast-lane PR here, same as
`trellis`.

Don't run `bin/install --enable` and don't touch the live crontab from a session working on this
repo's code — installing/enabling is a deploy step the user drives once a PR is merged.
