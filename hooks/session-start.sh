#!/bin/bash
# SessionStart hook:
# 1. Fast-forward the knowledge repo so the session starts on current state
# 2. Restore pre-compaction context if a recovery file exists
set -uo pipefail
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
KB="$HOME/projects/trellis-knowledge"
PULL_NOTE=""
if [ -d "$KB/.git" ]; then
  if ! timeout 20 git -C "$KB" pull --ff-only -q 2>/dev/null; then
    PULL_NOTE=$'WARNING: could not fast-forward trellis-knowledge (offline, diverged, or dirty). Run /sync before trusting state.\n\n'
  fi
fi
# Bring this session's own checkout of the agent repo up to origin/main, if that's a pure fast-forward
# and the tree is clean. Each session runs in its own worktree, so merges to main don't reach it otherwise.
# Only on a fresh start: never swap a session's config underneath it on resume or compaction.
SOURCE=$(echo "$INPUT" | jq -r '.source // empty')
AGENT_DIR="${CLAUDE_PROJECT_DIR:-}"
AGENT_WARN=$'WARNING: could not update this checkout of the agent repo to origin/main (offline, dirty tree, lock contention, or an untracked file in the way). Agent config may be stale; run /sync.\n\n'
FETCHED=0
if [ "$SOURCE" = "startup" ] && [ -n "$AGENT_DIR" ] && git -C "$AGENT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  if git -C "$AGENT_DIR" diff --quiet && git -C "$AGENT_DIR" diff --cached --quiet \
     && timeout 20 git -C "$AGENT_DIR" fetch -q origin main 2>/dev/null; then
    FETCHED=1
  else
    PULL_NOTE+="$AGENT_WARN"
  fi
fi
if [ "$FETCHED" = 1 ]; then
  if [ "$(git -C "$AGENT_DIR" rev-parse HEAD)" != "$(git -C "$AGENT_DIR" rev-parse FETCH_HEAD)" ]; then
    if git -C "$AGENT_DIR" merge-base --is-ancestor HEAD FETCH_HEAD; then
      if git -C "$AGENT_DIR" symbolic-ref -q HEAD >/dev/null; then
        git -C "$AGENT_DIR" merge -q --ff-only FETCH_HEAD 2>/dev/null
      else
        git -C "$AGENT_DIR" checkout -q --detach FETCH_HEAD 2>/dev/null
      fi && PULL_NOTE+=$'Agent config updated to origin/main at session start. AGENTS.md changes apply from the next launch.\n\n' \
         || PULL_NOTE+="$AGENT_WARN"
    else
      PULL_NOTE+=$'NOTE: this checkout of the agent repo has commits not on origin/main, so it was not updated. Merge origin/main when that work is done.\n\n'
    fi
  fi
fi
HANDOFF_FILE="${CLAUDE_PROJECT_DIR:-.}/.state/handoff/${SESSION_ID}.md"
if [ -n "$SESSION_ID" ] && [ -f "$HANDOFF_FILE" ]; then
  jq -n --arg note "$PULL_NOTE" --arg ctx "$(cat "$HANDOFF_FILE")" \
    '{"additionalContext": ($note + "This session just compacted. Conversation detail is gone but state on disk is intact. Follow the Recovery Procedure below before responding.\n\n" + $ctx)}'
elif [ -n "$PULL_NOTE" ]; then
  jq -n --arg note "$PULL_NOTE" '{"additionalContext": $note}'
fi
exit 0
