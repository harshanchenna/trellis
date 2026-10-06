# Trellis

Trellis is a template for a single-user, persistent Claude Code agent: one that keeps a stable identity across sessions, accumulates knowledge instead of losing it at every context reset, and can run scheduled work unattended. It is not a framework or a multi-tenant product. It's a starting point for building an agent that works for one person, on their own stuff.

MIT licensed. See `LICENSE`.

## Architecture

Trellis splits into three repos, each with its own git flow:

| Repo (clone to `~/projects/`) | Holds | Git flow |
|---|---|---|
| `trellis` (this repo) | identity (`AGENTS.md`), `skills/`, `agents/`, `hooks/`, `.mcp.json`, `.claude/` adapter | branch → PR → lane |
| `trellis-knowledge` | everything the agent knows | commit straight to main, no PRs |
| `trellis-cron` | scheduled jobs: job files, runner, a `ping` helper, systemd timers | branch → PR → lane |

**Identity.** `AGENTS.md` is the agent's source of truth: who it serves, its invariants, how it behaves. `CLAUDE.md` just imports it (`@AGENTS.md`), so the same file works if you later add another harness. `skills/` holds procedures with no personal context baked in — they all say "the user," never a name. `agents/` holds subagent definitions (a `researcher` agent ships as an example). `hooks/` wires a `SessionStart` hook (pulls the knowledge repo, restores pre-compaction context if present) and a `PreCompact` hook (writes a recovery document before context is cleared).

**Knowledge tiers.** The knowledge repo is split by how often it's touched, not by topic:
- **Hot** — `memory/MEMORY.md`, an index, auto-loaded every session, capped small on purpose.
- **Warm** — `memory/*.md` (native memory files: user, feedback, project, reference) and `projects/<p>.md`, one doc per project/domain with its current state. Read the matching project doc before working in that domain.
- **Cold** — `docs/<p>/`, deep material found through a manifest file, not loaded in bulk.
- **Living logs** — an alerts file and rotating weekly rollups that hold only current state; resolved items get deleted and git history is the record.

**State ritual.** At the end of meaningful work, the agent runs `/update-state`: it updates the relevant project doc, files any cold docs, and commits + pushes the knowledge repo. Nothing persists unless it goes through this step — the next session starts from a fresh pull of the knowledge repo and nothing else.

**Scheduled jobs.** `trellis-cron` owns cadence: a job file says which skill runs, with what prompt, on what schedule, and where output goes. Unattended jobs act only within their latitude (reversible, non-outward-facing actions their skill allows) and otherwise record the result silently. A `ping` helper reaches the user, but only when something is blocked on them (a decision, credential, or approval only they can give) or critical (data loss, a service down, a deadline within days). A normal day produces no ping.

**Review lanes.** Changes to `trellis` and `trellis-cron` go through a PR even though the agent can merge some of them itself:
- **Fast** — config tuning, hotfixes outside `skills/`/`agents/`/`hooks/`, dead-config removal, docs: the agent merges once pushed.
- **Reviewed** — changes to `skills/`, `agents/`, `hooks/`, or the agent's own rules: `/code-review` first, then the agent merges.
- **User merges** — architecture changes, changes to the review gate itself, loosening an invariant, or anything that widens the agent's access (new MCP server, new permission, a hook that does more): the user's call, not the agent's.

Every repo the agent doesn't own gets a human merge; invariant 1 holds everywhere — nothing goes to an external repo until the user has previewed the full body.

## Repo layout (this repo)

    AGENTS.md       source of truth (CLAUDE.md just imports it)
    skills/         procedures, no job context
    agents/         subagent definitions
    hooks/          session-start (pull knowledge, restore after compaction), pre-compact (write recovery file)
    .mcp.json       MCP servers you've wired up; a private server should read its own key from .env
    .claude/        Claude Code adapter: settings.json + symlinks to skills/ and agents/
    templates/      starter skeletons for trellis-knowledge and trellis-cron

## Quick start

    git clone <your-fork-url> ~/projects/trellis
    cd ~/projects/trellis
    claude

Then inside the session, run `/setup`. It interviews you on what the agent is for, checks prerequisites, creates or clones the knowledge repo (seeded from `templates/knowledge/`), wires up memory and `.env`, optionally sets up the scheduled-jobs repo (seeded from `templates/cron/`), and verifies each step.

The agent exists only when launched from this repo. Nothing is installed into global `~/.claude` config. A different harness gets its own adapter directory next to `.claude/`; `AGENTS.md`, `skills/`, `agents/` stay as they are.

## Shipped skills

| Skill | What it does |
|---|---|
| `setup` | Guided first-run setup: interview, prerequisites, knowledge/cron repo bootstrap, verification. |
| `startup` | Orient at the start of a session or after compaction: sync knowledge, read project state, report what changed. |
| `sync` | Bring the three repos in line with their remotes and report anything uncommitted, unpushed, or diverged. |
| `recall` | Retrieve past work, decisions, or project context from the knowledge repo. |
| `update-state` | Persist what a session learned and did into the knowledge repo, then commit and push. |
| `init-project` | Create a new project/domain in the knowledge repo, or change an existing one's scope. |
| `spec` | Produce a durable spec artifact before doing the work: an implementation issue, a design doc, or a research brief. |
| `research` | Structured research: a quick inline lookup, a deep multi-agent dig, or a full staged sprint with persistent artifacts. |
| `reddit` | Read a subreddit, search within it, or read a thread and its comments, through Reddit's public feeds. |
| `pr` | The full issue → branch → implement → verify → PR → review loop, then merge or hand off for merge. |
| `code-review` | Review a pull request for bugs, logic errors, and repo-convention compliance. |
| `design-review` | Review a pull request for architectural fit, feasibility, and completeness. |
| `skill-builder` | Build a new skill from an idea, or rework an existing one, through design, a quick test, and `/pr` + `/code-review`. |
| `cron-builder` | Turn an existing skill or script into a scheduled job: cadence, latitude, the job file, and a proven systemd run. |
| `self-improve` | Review how the agent has been performing and propose one concrete improvement to its own config as a PR. |
| `dream` | Nightly consolidation: reconcile the last day into memory and project docs, audit older memory, prune stale rollups. |
| `publish-trellis` | Export a generalized, secret-scanned snapshot of your private agent into a public template repo like this one, gated by an allowlist and a denylist scan, for your own review before you ever push it. |

## Templates for the other two repos

`templates/knowledge/` and `templates/cron/` hold starter skeletons for `trellis-knowledge` and `trellis-cron`: empty directory structure, a starter `MEMORY.md`, example project docs, a manifest script, a job-file format, and the `ping` helper. `/setup` copies from these when it bootstraps the other two repos; you can also use them by hand if you want to see the shape before running setup.

## Changing config

Branch → PR → `/code-review`. `/self-improve` proposes changes the same way.
