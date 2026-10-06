---
name: cron-builder
description: "Schedule an existing skill or script as a trellis-cron job: align on cadence and latitude, write the .job file and README row, review it, then install the timer and prove it with a real systemd run. Use when the user says 'run X every day/week', 'schedule X', 'make a cron for X', or /cron-builder."
argument-hint: "<skill or script> [schedule]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Skill(pr *), Skill(code-review *), Skill(skill-builder *)
---

# /cron-builder

Wires work that already exists into `~/projects/trellis-cron`. Read that repo's `AGENTS.md` and `README.md` first; they define the `.job` format and the rules. This skill doesn't restate them.

## 0. Does the thing to schedule exist?

- **A `claude` job needs a skill in `trellis/skills/`.** If there isn't one, run `/skill-builder` first. Jobs own the schedule and the prompt; skills own the procedure.
- **A `script` job needs a script in `trellis-cron/scripts/`.** A deterministic check doesn't need Claude, and script jobs are cheaper and can't be steered.
- **Check `jobs/*.job` for an existing job** that already covers it, or that runs at the same slot and writes the same files.

## 1. Align (questions)

Ask 2–3 questions with `AskUserQuestion`, each with a recommended default. If the request already states a value (e.g. a schedule), confirm it in one line instead of asking:
- **Cadence:** when it should run, in local wall-clock time. Put it after the jobs it depends on, e.g. after an earlier run if it reads that run's output.
- **Latitude:** what the job may fix on its own, and what it only records. Anything invariant 8 covers is never done unattended.
- **Noise:** when it pings. The default is silence; ping only when something is blocked on the user or critical.

## 2. Make the skill fit for unattended runs

`run-job` reads the allowlist from the skill's `allowed-tools`. A headless run refuses anything not on it, so check the skill before writing the job:
- `allowed-tools` uses per-command `Bash(...)` entries. Bare `Bash` or `Bash(git:*)` is too wide for an unattended run.
- File writes use the Write tool, not Bash `mkdir` or redirection; writes outside the working directory are refused.
- **Untrusted input** (email, web pages, third-party APIs) means `PERMISSION_MODE=dontAsk`, and the skill's allowlist must have no outward actions at all.
- No `Agent` in a scheduled skill's `allowed-tools`. Subagent types carry their own, wider tool sets, so a headless run could reach past the job's allowlist. Treat it as a hard stop.
- Its commits to the knowledge repo are path-limited (`-- <paths>`) and pushed with `scripts/kb-push`.

Fix any gaps in the skill through its own lane (`/pr`, reviewed) before the job lands.

## 3. Write the job

Do this in a trellis-cron worktree under `~/projects/.worktrees/`:
- `jobs/<name>.job`: `SCHEDULE`, `KIND`, `PROJECT`, `TIMEOUT_MIN`, `DESCRIPTION`, `SUCCESS`. A claude job also needs `PROMPT`. Prefer `kb-commit:<path>` for `SUCCESS` when the job's whole point is a doc. Comment any `ALLOWED_TOOLS` or `DISALLOWED_TOOLS` override and say why.
- Add the job to the schedule table in `README.md`.

## 4. Review and ship

- A new job adds unattended work, so it goes through the **Reviewed** lane: full `/code-review`, fix the findings, merge.
- **The user merges** if the job widens access. Examples: an `ALLOWED_TOOLS` override broader than the skill's list, `PERMISSION_MODE` loosened for untrusted input, or a job that pushes or posts somewhere new.

## 5. Install and prove

Enabling a timer is a deploy step the user drives (trellis-cron `AGENTS.md`). It also touches shared ground, so message the running sessions first.
1. Fast-forward the main clone. Ask the user to run `bin/install --enable`. Never run it yourself.
2. **Prove the job with a real systemd run, not a shell:** `systemctl --user start trellis-cron-<name>.service`. Interactive shells have a different PATH and environment; a smoke test from a shell can pass while every scheduled run fails (`claude` not on the systemd PATH).
3. Read `~/.local/state/trellis-cron/<name>/last.json`. You need exit 0, `is_error` false, and no `permission_denials`. Fix any denial in the skill's allowlist, then run it again.
4. Confirm that `systemctl --user list-timers` shows the next run.

Record the job in the owning project's doc, then run `/update-state`.
