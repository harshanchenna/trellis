# trellis-cron

Scheduled work for the agent: job definitions (schedule + prompt), the runner, the Discord alert
helper, and the deterministic health check. Pick one timezone for all schedules and stick to it;
jobs in the same slot run in parallel as separate sessions.

## What runs when

| Time | Job | Kind | Project | Pings when |
|---|---|---|---|---|
| 06:00 daily | `dream` | Claude | self-improve | a decision is truly the user's to make |
| 07:00 daily | `cron-health` | plain script, no Claude | self-improve | any job didn't run, failed, or (for a claude job) had a permission denial, with triage steps |

These two are the shipped starting point. Add your own jobs the same way (see "Add a job" below)
and extend this table.

A normal day produces no pings — jobs fix what's in their latitude, record it, and commit
silently. See each `jobs/<name>.job` for the exact schedule expression, prompt, and tool
allowlist.

## Where logs and status live

- Per-run log: `~/.local/state/trellis-cron/<name>/<UTC timestamp>.log`
- Latest status: `~/.local/state/trellis-cron/<name>/last.json` — `{job, start_utc, end_utc,
  exit, duration_s, log}`
- Logs older than 30 days are pruned automatically by `bin/run-job`.
- Open alerts: `~/projects/trellis-knowledge/alerts.md` (`## Cron` section) — current failures
  only, resolved ones are deleted; git history is the record.

## Check health

    bin/cron-health --dry-run     # see what it would find/ping, without pinging or committing
    bin/cron-health               # the real check (also runs automatically at 07:00)
    systemctl --user list-timers 'trellis-cron-*'
    cat ~/.local/state/trellis-cron/<name>/last.json

`cron-health` checks every job's schedule for the latest slot that should already have fired (as
of now, minus a grace window) against the last 26 hours: did that slot's run happen, exit 0, and
satisfy its `SUCCESS` condition — and for a claude job, did it come back clean (no `is_error`, no
permission denials) — and is its timer enabled and active. A job whose lock is currently held is
treated as running, not missed. It's silent when everything's green.

## Rerun a job by hand

    bin/run-job <name>

Takes a per-job lock, so it's safe even if the timer is about to fire too — the second one just
waits/skips rather than overlapping.

## Add a job

1. Add `jobs/<name>.job`. See `AGENTS.md` for the field reference. Tool allowlists come from the
   skill's own `SKILL.md` `allowed-tools` frontmatter, not the job file — get that right in the
   skill first. If the job will read untrusted external content, set `PERMISSION_MODE=dontAsk`,
   and consider a `DISALLOWED_TOOLS` backstop for anything that must never happen unattended.
2. `bin/install` (no flags) to write its unit files and run `daemon-reload`; inspect them under
   `~/.config/systemd/user/`.
3. `bin/install --enable` to actually turn it on. (Not run casually — see `AGENTS.md`'s PR flow;
   this is a deploy step driven after merge, not something a working session does mid-PR.)
4. Update the table above.

## Install / uninstall

    bin/install               # write unit files + daemon-reload only, nothing enabled
    bin/install --enable      # also enable and start every timer
    bin/install --uninstall   # disable, stop, and remove every trellis-cron unit

## Sending an alert

    bin/ping "short trusted status line"            # a literal a script builds itself
    bin/ping --file /path/to/message.txt             # message from a file
    some-command | bin/ping -                        # message from stdin
    bin/ping "message" --record Cron                 # also append a dated line to
                                                       # trellis-knowledge/alerts.md's ## Cron
                                                       # section and push it

Use `--file`/`-` for anything derived from outside the job's own script (email content, a web
page, an API response) — never put untrusted text on the command line. The message is sanitized
(Discord mentions stripped) and truncated before it's sent either way.

## Secrets

Nothing sensitive lives in this repo. `bin/ping` reads `DISCORD_BOT_TOKEN` and
`DISCORD_ALERT_USER_ID` from `~/projects/trellis/.env` at the point of use and sends the alert as
a DM through your Discord bot (no webhook or channel). Copy `.env.example` → `.env` and fill it
in if a job of yours needs its own secrets. Never printed, sourced wholesale, or committed —
`bin/ping` uses the token inside python, never argv, so it never shows up in `ps` either.
