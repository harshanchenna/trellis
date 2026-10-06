# templates

Starting skeletons for the two sibling repos the agent expects alongside it:

- `knowledge/` → copied out to `~/projects/trellis-knowledge` (or your chosen name): the agent's
  memory, project docs, and cold docs. Pure state, no code.
- `cron/` → copied out to `~/projects/trellis-cron` (or your chosen name): the scheduled-job
  runner, a Discord alert helper, a health check, and two example jobs (`dream`, `cron-health`).

`/setup` copies these out and wires paths, timezone, and secrets for your machine. You can also
copy them by hand if you're not running `/setup`.
