#!/bin/bash
# PreCompact hook v3 — capture recovery context before compaction.
# Writes a recovery document to .state/handoff/{session_id}.md (gitignored, repo-local)
# session-start.sh injects this into the next session's context.
#
# v2 additions vs v1 (2026-05-27):
#   - PR / issue lifecycle from `gh`
#   - jobs/*/state.json summaries
#   - Skill invocations extracted (not filtered as noise)
#   - Background Agent tool calls + their task IDs / descriptions
#   - Tool result summaries (Bash + Read + Write, capped)
#   - Better noise filter (task-notification, channel source, local-command-caveat)
#   - Timestamps on user requests
#
# v3 (2026-10-14): leaner (v2 docs were ~65KB, mostly other projects' threads).
#   - Points at the session's own project doc(s) instead of copying every project's open threads
#   - User requests are the user's own messages only (transcript origin field), last 5, near-verbatim
#   - Drops the keyword-guessed decisions/errors sections
set -euo pipefail

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TRANSCRIPT=$(echo "$INPUT"  | jq -r '.transcript_path // empty')
TRIGGER=$(echo "$INPUT"     | jq -r '.trigger // "auto"')
CWD=$(echo "$INPUT"         | jq -r '.cwd // ""')

# Nothing to do without a session ID
if [ -z "$SESSION_ID" ]; then
  exit 0
fi

HANDOFF_DIR="${CLAUDE_PROJECT_DIR:-$CWD}/.state/handoff"
mkdir -p "$HANDOFF_DIR"

# Export vars for the Python script
export HOOK_SESSION_ID="$SESSION_ID"
export HOOK_TRANSCRIPT="$TRANSCRIPT"
export HOOK_TRIGGER="$TRIGGER"
export HOOK_CWD="$CWD"
export HOOK_OUTPUT="$HANDOFF_DIR/${SESSION_ID}.md"

python3 - <<'PYEOF'
import json, os, re, glob, subprocess
from datetime import datetime, timezone

session_id  = os.environ.get("HOOK_SESSION_ID", "")
transcript  = os.environ.get("HOOK_TRANSCRIPT", "")
trigger     = os.environ.get("HOOK_TRIGGER", "auto")
cwd         = os.environ.get("HOOK_CWD", "")
output_path = os.environ.get("HOOK_OUTPUT", "")

timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def sh(cmd, timeout=8, cwd_arg=None):
    """Run a shell command with timeout. Return stdout or empty string."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                           cwd=cwd_arg or cwd)
        return r.stdout.strip()
    except Exception:
        return ""

# ── Parse transcript ──────────────────────────────────────────────
messages = []        # (role, text, ts, human) — text from user/assistant; human=True when the
                     # transcript marks a user turn as typed by the user (origin.kind == "human")
tool_uses = []       # (name, input_summary, result_summary, ts)
skill_invocations = [] # (skill_name, args, ts)
agent_dispatches = [] # (description, subagent_type, prompt_first_line, ts)
agent_name = ""      # e.g. "agent: homelab" (the session's name, set by the launcher)

if transcript and os.path.exists(transcript):
    try:
        with open(transcript) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    d = json.loads(line)
                except (json.JSONDecodeError, KeyError):
                    continue
                if not isinstance(d, dict):
                    continue

                ts_raw = d.get("timestamp", "")  # iso format if present
                if d.get("agentName"):
                    agent_name = str(d["agentName"])
                msg = d.get("message", {}) or {}
                role = msg.get("role", "")
                content = msg.get("content", "")
                # Peer sessions, subagent hand-backs, notifications and scheduled prompts also arrive as
                # user turns. Newer transcripts say who sent each one; drop anything not typed by the user.
                origin = d.get("origin") if isinstance(d.get("origin"), dict) else {}
                okind = origin.get("kind")
                if role == "user" and ((okind and okind != "human") or d.get("isMeta")):
                    continue  # isMeta: skill bodies, scheduled prompts, harness notices
                human = role == "user" and okind == "human"

                if isinstance(content, list):
                    for c in content:
                        if not isinstance(c, dict):
                            continue
                        c_type = c.get("type", "")
                        if c_type == "text":
                            text = (c.get("text", "") or "").strip()
                            if text and role in ("user", "assistant"):
                                messages.append((role, text, ts_raw, human))
                        elif c_type == "tool_use":
                            name = c.get("name", "")
                            inp = c.get("input", {}) or {}
                            # Extract a one-line summary of the tool call
                            if name == "Skill":
                                skill_name = inp.get("skill", "")
                                args = inp.get("args", "") or ""
                                skill_invocations.append((skill_name, args[:200], ts_raw))
                            elif name == "Agent":
                                desc = inp.get("description", "")
                                stype = inp.get("subagent_type", "general-purpose")
                                prompt = (inp.get("prompt", "") or "").split("\n", 1)[0][:200]
                                agent_dispatches.append((desc, stype, prompt, ts_raw))
                            else:
                                # Build a one-line summary for other tools
                                if name == "Bash":
                                    summary = (inp.get("description") or inp.get("command", ""))[:160]
                                elif name in ("Read", "Edit", "Write"):
                                    summary = inp.get("file_path", "")[:160]
                                elif name == "Grep":
                                    summary = (inp.get("pattern", "") + " " + (inp.get("path", "") or ""))[:160]
                                else:
                                    summary = json.dumps(inp)[:160]
                                tool_uses.append((name, summary, "", ts_raw))
                        elif c_type == "tool_result":
                            # tool_result has content (string or list). Capture first 200 chars of text.
                            tr = c.get("content", "")
                            if isinstance(tr, list):
                                tr_text = " ".join(
                                    x.get("text", "") for x in tr
                                    if isinstance(x, dict) and x.get("type") == "text"
                                )
                            else:
                                tr_text = str(tr)
                            tr_text = tr_text.strip().replace("\n", " ")[:200]
                            # Attach to the most recent tool_use without a result
                            if tool_uses and tool_uses[-1][2] == "":
                                tool_uses[-1] = (tool_uses[-1][0], tool_uses[-1][1], tr_text, tool_uses[-1][3])
                elif isinstance(content, str):
                    text = content.strip()
                    if text and role in ("user", "assistant"):
                        messages.append((role, text, ts_raw, human))
    except OSError:
        pass

# ── Noise filter (refined v2) ─────────────────────────────────────
NOISE_PATTERNS = [
    "Base directory for this skill:",         # skill body (we capture invocation separately)
    "<system-reminder>",
    "<task-notification>",
    "<local-command-caveat>",
    "[SYSTEM NOTIFICATION - NOT USER INPUT]",
    "This is an automated background-task event",
    "This session is being continued from a previous conversation",
    "Tool loaded.",                            # ToolSearch result fluff
    "Caveat: The messages below were generated by the user while running local commands",
    "[Request interrupted by user]",
]
# Fallback for transcripts without origin: peer and subagent messages start with this line.
# Matched only at the start, so the user quoting the phrase isn't dropped.
PEER_PREFIX = "Another Claude session sent a message"
def is_noise(text, human=False):
    if not text:
        return True
    if human:
        return False
    return text.startswith(PEER_PREFIX) or any(p in text for p in NOISE_PATTERNS)

# ── Extract user requests + files referenced ──────────────────────
user_requests = []     # (ts, text)
files_seen    = set()

for role, text, ts, human in messages:
    if is_noise(text, human):
        continue
    if role == "user":
        user_requests.append((ts, text[:1500].replace("\n", " ").strip()))
    elif role == "assistant":
        for p in re.findall(r'(?:docs/|projects/|memory/|skills/|agents/|hooks/|~/)[\w/.\-]+\.(?:md|json|py|sh|tex|yml|yaml|ts|js)', text):
            files_seen.add(p)

# ── Git state ─────────────────────────────────────────────────────
git_branch       = sh(["git", "branch", "--show-current"])
git_diff_stat    = sh(["git", "diff", "--stat"])
git_staged_stat  = sh(["git", "diff", "--cached", "--stat"])
git_recent       = sh(["git", "log", "--oneline", "-10"])
git_stash_list   = sh(["git", "stash", "list"])[:500]

# ── PR / Issue state (gh CLI) ─────────────────────────────────────
# Detect repo from origin remote, then list PRs/issues. Bound to short timeouts.
gh_remote = sh(["git", "remote", "get-url", "origin"])
gh_repo = ""
m = re.search(r'github\.com[:/]([^/]+/[^/.]+)', gh_remote or "")
if m:
    gh_repo = m.group(1)

pr_summary = ""
issue_summary = ""
if gh_repo:
    pr_json = sh(["gh", "pr", "list", "-R", gh_repo, "--state", "open",
                  "--json", "number,title,updatedAt,reviewDecision", "--limit", "10"], timeout=6)
    try:
        prs = json.loads(pr_json) if pr_json else []
        if prs:
            pr_summary = "Open PRs:\n"
            for p in prs:
                pr_summary += f"- #{p['number']} {p['title']} (updated {p['updatedAt'][:10]}, review: {p.get('reviewDecision') or 'none'})\n"
    except Exception:
        pass

    # Recently merged PRs (last 5 of any state, then filter merged in window)
    pr_merged = sh(["gh", "pr", "list", "-R", gh_repo, "--state", "merged",
                    "--json", "number,title,mergedAt", "--limit", "5"], timeout=6)
    try:
        merged = json.loads(pr_merged) if pr_merged else []
        if merged:
            pr_summary += "\nRecently merged PRs:\n"
            for p in merged:
                pr_summary += f"- #{p['number']} {p['title']} (merged {p['mergedAt'][:10]})\n"
    except Exception:
        pass

    issue_json = sh(["gh", "issue", "list", "-R", gh_repo, "--state", "open",
                     "--json", "number,title,updatedAt", "--limit", "8"], timeout=6)
    try:
        issues = json.loads(issue_json) if issue_json else []
        if issues:
            issue_summary = "Open issues:\n"
            for i in issues:
                issue_summary += f"- #{i['number']} {i['title']} (updated {i['updatedAt'][:10]})\n"
    except Exception:
        pass

job_states = []  # no scheduled jobs in this setup

# ── Open threads from project state docs ──────────────────────────
# Only the session's own project(s): the one its name points at ("agent: homelab" -> homelab),
# plus the project doc it mentioned most. Other projects' threads are noise after a compaction.
proj_dir = os.path.expanduser("~/projects/trellis-knowledge/projects")
all_projects = sorted(os.path.basename(p)[:-3] for p in glob.glob(os.path.join(proj_dir, "*.md")))
mine = []
named = agent_name.split(":", 1)[-1].strip().lower() if agent_name else ""
if named in all_projects:
    mine.append(named)
counts = {}
for _, text, _, human in messages:
    if is_noise(text, human):
        continue
    for p in re.findall(r'projects/([\w\-]+)\.md', text):
        if p in all_projects:
            counts[p] = counts.get(p, 0) + 1
for p, _ in sorted(counts.items(), key=lambda kv: -kv[1]):
    if p not in mine and len(mine) < 2:
        mine.append(p)

# Point at the docs rather than copying them: they're on disk and current, and a copy of every
# thread (v2) was most of the handoff's size.
track_summary = ""
if mine:
    track_summary = "Read Current state and Open threads in: " + ", ".join(
        f"`~/projects/trellis-knowledge/projects/{p}.md`" for p in mine) + "\n"
elif all_projects:
    track_summary = ("No project identified for this session. Read the one matching the work in "
                     "flight, under `~/projects/trellis-knowledge/projects/`: " + ", ".join(all_projects) + "\n")

latest_handoff_doc = ""

# ── Build the recovery document ───────────────────────────────────
def section(header, body):
    return [f"## {header}", "", body, ""] if body else []

lines = [
    "# Compaction Recovery Context",
    "",
    f"**Session**: {session_id}" + (f" ({agent_name})" if agent_name else ""),
    f"**Timestamp**: {timestamp}",
    f"**Trigger**: {trigger}",
    f"**CWD**: {cwd}",
    f"**Branch**: {git_branch}",
    "",
    "## Recovery Procedure",
    "",
    "Run `/startup` to orient fully. Quick path:",
    "1. AGENTS.md and MEMORY.md auto-load.",
    "2. Read the project state doc(s) named under This Session's Project Docs (or `trellis-knowledge/projects/<p>.md` for whatever was in flight).",
    "3. Scan open PRs + issues below to ground in active work.",
    "4. If this session did meaningful work that is not yet saved, run `/update-state`.",
    "",
]

if latest_handoff_doc:
    lines += [
        "## :star: Latest Handoff Doc (read FIRST)",
        "",
        f"`{latest_handoff_doc}`",
        "",
        "This was written manually before compaction and carries richer detail than this auto-recovery file.",
        "",
    ]

if user_requests:
    lines += ["## Recent User Requests (newest first)", ""]
    for ts, req in list(reversed(user_requests))[:5]:
        ts_short = ts[:19] if ts else "?"
        lines.append(f"- `{ts_short}` {req}")
    lines.append("")

if skill_invocations:
    lines += ["## Skills Invoked This Session", ""]
    for skill_name, args, ts in skill_invocations[-15:]:
        ts_short = ts[:19] if ts else "?"
        args_str = f" `{args}`" if args else ""
        lines.append(f"- `{ts_short}` /{skill_name}{args_str}")
    lines.append("")

if agent_dispatches:
    lines += ["## Background / Subagent Dispatches", ""]
    for desc, stype, prompt, ts in agent_dispatches[-10:]:
        ts_short = ts[:19] if ts else "?"
        lines.append(f"- `{ts_short}` **{desc}** (subagent: `{stype}`) — {prompt}")
    lines.append("")

lines += ["## Git State", ""]
if git_diff_stat or git_staged_stat:
    lines.append("**Uncommitted changes:**")
    if git_staged_stat:
        lines += ["", "_Staged:_", "```", git_staged_stat, "```"]
    if git_diff_stat:
        lines += ["", "_Unstaged:_", "```", git_diff_stat, "```"]
    lines.append("")
if git_recent:
    lines += ["**Recent commits:**", "```", git_recent, "```", ""]
if git_stash_list:
    lines += ["**Stashes (may contain orphaned work):**", "```", git_stash_list, "```", ""]

if pr_summary or issue_summary:
    lines += ["## GitHub State", ""]
    if pr_summary:
        lines.append(pr_summary)
    if issue_summary:
        lines.append(issue_summary)

if job_states:
    lines += ["## Cron Job States", ""]
    lines += job_states
    lines.append("")

if track_summary:
    lines += ["## This Session's Project Docs", "", track_summary]

if tool_uses:
    # Tail of significant tool uses — Bash + Edit + Write. Skip Read (too noisy).
    sig_tools = [(n, s, r, t) for (n, s, r, t) in tool_uses if n in ("Bash", "Edit", "Write")]
    if sig_tools:
        lines += ["## Recent Significant Tool Actions (Bash/Edit/Write)", ""]
        for name, summary, result, ts in sig_tools[-15:]:
            ts_short = ts[:19] if ts else "?"
            line = f"- `{ts_short}` **{name}**: {summary}"
            if result:
                line += f" → {result[:120]}"
            lines.append(line)
        lines.append("")

if files_seen:
    lines += ["## Files Referenced in Conversation", ""]
    for fp in sorted(files_seen)[:25]:
        lines.append(f"- `{fp}`")
    lines.append("")

# Recent conversation (text-only, filtered)
filtered = [(r, t, ts) for (r, t, ts, h) in messages if not is_noise(t, h)]
recent = filtered[-6:]
if recent:
    lines += [f"## Recent Conversation (last {len(recent)} meaningful messages)", ""]
    for role, text, ts in recent:
        ts_short = ts[:19] if ts else "?"
        snippet = text[:600].replace("\n", " ").strip()
        lines.append(f"**{role}** (`{ts_short}`): {snippet}")
        lines.append("")

lines += [
    "## Key State Files",
    "",
    "- `~/projects/trellis-knowledge/memory/MEMORY.md` — hot index (auto-loads)",
    "- `~/projects/trellis-knowledge/projects/<p>.md` — latest state per project",
    "- `~/projects/trellis-knowledge/docs/manifest.json` — index of cold docs",
    "",
]

with open(output_path, "w") as f:
    f.write("\n".join(lines))
PYEOF
