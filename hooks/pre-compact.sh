#!/bin/bash
# PreCompact hook v2 — capture rich recovery context before compaction.
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
#   - Timestamps on user requests + decisions
#   - Broader decision/error keyword detection
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
messages = []        # (role, text, ts) — only text content from user/assistant
tool_uses = []       # (name, input_summary, result_summary, ts)
skill_invocations = [] # (skill_name, args, ts)
agent_dispatches = [] # (description, subagent_type, prompt_first_line, ts)

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

                ts_raw = d.get("timestamp", "")  # iso format if present
                msg = d.get("message", {}) or {}
                role = msg.get("role", "")
                content = msg.get("content", "")

                if isinstance(content, list):
                    for c in content:
                        if not isinstance(c, dict):
                            continue
                        c_type = c.get("type", "")
                        if c_type == "text":
                            text = (c.get("text", "") or "").strip()
                            if text and role in ("user", "assistant"):
                                messages.append((role, text, ts_raw))
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
                        messages.append((role, text, ts_raw))
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
]
def is_noise(text):
    if not text:
        return True
    return any(p in text for p in NOISE_PATTERNS)

# ── Extract user requests + assistant decisions/errors ────────────
DECISION_KW = [
    "decided", "going with", "chose", "recommendation:", "my take:",
    "approve", "approved", "let's go with", "verdict", "the answer is",
    "agreed", "consensus", "rec:", "recommend", "the move is",
]
ERROR_KW = [
    "error:", "failed:", "bug:", "broken", "fix needed", "blocker",
    "regression", "critical:", "rotating_light", ":x:",
]

user_requests = []     # (ts, snippet)
decisions     = []     # (ts, snippet)
errors        = []     # (ts, snippet)
files_seen    = set()

for role, text, ts in messages:
    if is_noise(text):
        continue
    if role == "user":
        user_requests.append((ts, text[:240].replace("\n", " ").strip()))
    elif role == "assistant":
        lower = text.lower()
        if any(w in lower for w in DECISION_KW):
            decisions.append((ts, text[:300].replace("\n", " ").strip()))
        if any(w in lower for w in ERROR_KW):
            errors.append((ts, text[:300].replace("\n", " ").strip()))
        for p in re.findall(r'(?:docs/|projects/|memory/|skills/|agents/|hooks/)[\w/.\-]+\.(?:md|json|py|sh|tex|yml|yaml|ts|js)', text):
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
track_summary = ""
for path in sorted(glob.glob(os.path.expanduser("~/projects/trellis-knowledge/projects/*.md"))):
    try:
        with open(path) as f:
            content = f.read()
    except OSError:
        continue
    threads, on = [], False
    for line in content.split("\n"):
        if line.startswith("## Open threads"):
            on = True
            continue
        if on and line.startswith("## "):
            break
        if on and line.strip().startswith("- "):
            threads.append(line[:240])
    if threads:
        track_summary += f"**{os.path.basename(path)[:-3]}**\n" + "\n".join(threads) + "\n\n"

latest_handoff_doc = ""

# ── Build the recovery document ───────────────────────────────────
def section(header, body):
    return [f"## {header}", "", body, ""] if body else []

lines = [
    "# Compaction Recovery Context",
    "",
    f"**Session**: {session_id}",
    f"**Timestamp**: {timestamp}",
    f"**Trigger**: {trigger}",
    f"**CWD**: {cwd}",
    f"**Branch**: {git_branch}",
    "",
    "## Recovery Procedure",
    "",
    "Run `/startup` to orient fully. Quick path:",
    "1. AGENTS.md and MEMORY.md auto-load.",
    "2. Read the project state doc(s) for whatever was in flight (`trellis-knowledge/projects/<p>.md`).",
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
    for ts, req in list(reversed(user_requests))[:8]:
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

if decisions:
    lines += ["## Key Decisions This Session", ""]
    for ts, dec in decisions[-8:]:
        ts_short = ts[:19] if ts else "?"
        lines.append(f"- `{ts_short}` {dec}")
    lines.append("")

if errors:
    lines += ["## Errors / Issues Encountered", ""]
    for ts, err in errors[-6:]:
        ts_short = ts[:19] if ts else "?"
        lines.append(f"- `{ts_short}` {err}")
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
    lines += ["## Open Threads (from project state docs)", "", track_summary]

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
filtered = [(r, t, ts) for (r, t, ts) in messages if not is_noise(t)]
recent = filtered[-10:]
if recent:
    lines += [f"## Recent Conversation (last {len(recent)} meaningful messages)", ""]
    for role, text, ts in recent:
        ts_short = ts[:19] if ts else "?"
        snippet = text[:320].replace("\n", " ").strip()
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
