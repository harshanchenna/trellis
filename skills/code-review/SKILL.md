---
name: code-review
description: "Code review a pull request for bugs, logic errors, and repo-convention compliance. Supports --comment to post to GitHub and --deep for depth control."
allowed-tools: Bash(gh issue view:*), Bash(gh search:*), Bash(gh issue list:*), Bash(gh pr comment:*), Bash(gh pr diff:*), Bash(gh pr view:*), Bash(gh pr list:*), Bash(gh api:*), Bash(git rev-parse:*), Read, Glob, Grep, Agent
---

Provide a code review for the given pull request.

**`trellis-knowledge` is never the target of a PR or a review.** If asked to review something there, say so and stop — that repo takes direct commits, there's no PR to review.

**Agent assumptions (applies to all agents and subagents):**
- All tools are functional and will work without error. Do not test tools or make exploratory calls.
- Only call a tool if it is required to complete the task.
- Reviewer subagents see none of the orchestrator's context or memory — every dispatch prompt must be self-contained (PR intent, diff/context, and any repo-convention text quoted in full, not referenced by path).

## Depth Tiers

Parse arguments for depth. Default is **standard**.

| Flag | Level | Use For |
|------|-------|---------|
| *(default)* | Standard | All PRs |
| `--deep` | Deep | Security-critical code, cross-service integration, architecture changes, high-risk logic — only when explicitly requested |

**Model usage:**
- Pre-check, context gathering, PR summarizer: **Haiku**
- Compliance, bug detection, logic/security, and validation agents: **Sonnet**

**Severity levels:**
- **Critical**: Will break production, security vulnerability, data loss. Blocks merge.
- **Important**: Significant bug, logic error, clear convention violation. Should block merge.
- **Nit**: Style, suggestion, minor improvement. Never blocks.
- **Pre-existing**: Issue predates this PR. Flag for awareness, never blocks.

**Key principle:** the review reports findings with severity. It never says "do not merge" — the merge decision is made afterwards, by the user (the human owner, never this agent or another session), or on the agent's own repos by the **Merging** rule in `AGENTS.md`.

---

# Standard Review (default)

## Step 1: Pre-check (haiku agent)

Check whether: the PR is closed, is a draft, doesn't need review (automated/trivial), or has already been reviewed by this workflow (`gh pr view <PR> --comments`, look for prior review comments from this workflow). If any is true, stop.

Still review Claude-generated PRs — the point is to catch bugs, not to avoid reviewing AI output.

## Step 2: Gather repo conventions (haiku agent)

Launch a haiku agent to find and **read** (not just list) the repo's convention files for the changed paths:
- The root `AGENTS.md` or `CLAUDE.md`, whichever exists, **read from the PR's base branch** (`git -C <repo> show origin/<base>:AGENTS.md`), not from the PR branch. A PR must be judged against the rules that were in force before it, or a PR that weakens a rule passes by construction.
- Any nested `AGENTS.md`/`CLAUDE.md` in directories containing files the PR modifies

Return the actual text (or the relevant excerpts) — the orchestrator will paste this directly into each compliance reviewer's prompt in Step 4, since those subagents can't read the orchestrator's context and there's no rules layer to auto-inherit it from.

## Step 3: Summarize PR (haiku agent)

Return: PR title and description, files changed with brief purpose, overall intent.

## Step 4: Parallel review (4 sonnet agents)

Launch 4 agents in parallel. Each returns a list of issues with: file path and line number(s), description, and reason flagged (e.g. "convention violation", "bug", "logic error", "security"). Give every agent the PR title/description and the diff.

### Agents 1 + 2: Convention compliance (sonnet agents, redundant pair)
Give both agents the AGENTS.md/CLAUDE.md text gathered in Step 2 verbatim, plus the diff. Audit changes against it. Only flag a violation when the file being checked is covered by that convention file's scope (same path or a parent directory).

**If the PR modifies `skills/code-review/` or `skills/design-review/`**: review it using the procedure as it exists on the base branch (`git show origin/<base>:skills/code-review/SKILL.md`), never the PR's own version, and state in the output that the PR changes the review gate, so the user merges it. Make the same statement, naming the lane `AGENTS.md`'s **Merging** section reserves for the user, for any PR in that lane: it changes that paragraph, removes or loosens an invariant, widens the agent's access (`.mcp.json` servers or commands, `enabledMcpjsonServers`, `permissions`, hooks), or is a major re-architecture.

**If the PR modifies `AGENTS.md` or `CLAUDE.md`**: give one of the two compliance agents the base-branch and PR-branch versions side by side and have it list every invariant or rule that was removed, loosened, narrowed in scope, or given a new exception, quoting before and after. Each one is reported at **Important** or higher, even if intended, so the user sees it called out rather than buried in a diff. This matters most for `/self-improve` PRs.

### Agent 3: Bug detection (sonnet agent)
Scan for bugs **introduced in this diff only**, from the diff alone (no extra context). Severity as above. Don't flag anything that can't be validated from the diff.

### Agent 4: Logic & security (sonnet agent)
Look for problems **introduced in this diff**: security issues, incorrect logic, race conditions, resource leaks.

**HIGH SIGNAL ONLY.** Flag:
- Code that will fail to compile/parse
- Code that will definitely produce wrong results regardless of input
- Clear, quotable convention violations
- Security vulnerabilities (injection, auth bypass, secret exposure)

Do NOT flag: style/quality nits, input-dependent maybes, subjective suggestions, pedantic nitpicks, anything a linter would catch, lint-suppressed lines, missing test coverage (unless the conventions require it). If you're not certain, don't flag it.

## Step 5: Validate issues (parallel sonnet agents)

For each Step 4 issue, launch a validation agent with: PR title/description, the issue, and relevant code context. Confirm with high confidence — e.g. "variable undefined" → verify it actually isn't defined; "convention violation" → verify the rule is scoped to this file and actually violated.

## Step 6: Filter and output

Drop anything not validated in Step 5. Proceed to [Output](#output-format).

---

# Deep Review (`--deep`)

Standard Steps 1-5, then:

## Deep Step 6: Expanded context (2 sonnet agents in parallel)

### Agent 5: Full file context
For each changed file, read the **full file**. Check consistency with the rest of the file, inconsistencies with adjacent code, and missed related updates (e.g. a renamed function still called by its old name elsewhere in the file).

### Agent 6: Cross-codebase integration
Grep for usages of shared imports/constants/types the diff touches. Check API contracts match between caller/callee, config/env changes are reflected where consumed, shared model/schema changes are reflected in all consumers.

## Deep Step 7: Second validation pass

Validate all Step 5 + Step 6 survivors with full file context and any cross-codebase evidence. Only survivors go to output.

## Deep Step 8: Filter and output

---

# Output Format

## No issues

Post via `gh pr comment` (if `--comment`), else print:

```markdown
## Code Review

No issues found. Checked for bugs and repo-convention compliance.
```

## Issues found

Dedupe across agents, then post one PR comment (if `--comment`) or print:

```markdown
## Code Review

Found N issue(s): X critical, Y important, Z nit

### 1. [Brief title]
**File**: `path/to/file.py` (lines X-Y)
**Severity**: Critical | Important | Nit | Pre-existing
**Category**: Bug | Convention violation | Security | Logic error
**Description**: [...]
**Suggestion**: [How to fix, if straightforward]

[Link to code: https://github.com/OWNER/REPO/blob/FULL_SHA/path/file.py#LX-LY]

---

### 2. [Next issue...]
```

- Small self-contained fixes (<6 lines): include a code suggestion. Larger: describe the approach, not exact code.
- Resolve the full SHA with `git rev-parse HEAD` before building links; include ≥1 line of context before/after.
- Only one comment per unique issue — no duplicates.

---

# Notes

- Use `gh` CLI. Do not web-fetch GitHub.
- If `--comment` isn't given, print the review instead of posting.
- Cite/link each issue.
- Repo name must match the reviewed repo in every URL.
