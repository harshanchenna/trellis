---
name: pr
description: "Execute the full issue → branch → implement → verify → PR → review loop, then merge (agent repos) or hand off for merge (everything else). Use when implementing a GitHub issue or when asked to 'make a PR', 'ship this', or similar."
argument-hint: "[issue number, repo, or brief description]"
allowed-tools: Skill(code-review *), Skill(design-review *), Skill(spec *)
---

## Instructions

Run the full implementation workflow end-to-end. Don't ask the user to re-explain the flow.

Repos are local clones under `~/projects/<repo>` (for `trellis` and `trellis-cron`, branch work goes in a worktree; see step 2). Pass `-R owner/repo` to `gh` commands run from elsewhere.

**`trellis-knowledge` is never the target of a PR or a review.** If asked to `/pr` something there, say so and commit directly to main instead — skip the rest of this workflow.

### 1. Issue

If an issue number is given: `gh issue view <N>`.

If no issue exists: invoke `/spec --impl` to create one, or draft inline (Problem, Solution, Acceptance Criteria, Out of Scope, References). Present to the user for approval, then `gh issue create --title "..." --body "..."`.

When the user asked for the change in conversation, create the issue with their words quoted, and don't wait for approval.

**Exceptions** (skip the issue): the user says "skip issue" (note in the PR body: "Urgent fix, no prior issue"), it's a pure docs change, it's a revert, or it's a fast-lane change on `trellis` / `trellis-cron` (see **Merging** in `AGENTS.md`). Otherwise every PR needs one.

### 2. Branch

**`trellis` and `trellis-cron`**: first check whether another session is already doing agent work, and hand over if so (see **Agent changes** in `AGENTS.md`). Never switch the branch of a checkout a session runs from; work in a new worktree (`<slug>` is the branch name with `/` replaced by `-`):

```bash
git -C ~/projects/<repo> fetch origin main
git -C ~/projects/<repo> worktree add ~/projects/.worktrees/<repo>-<slug> -b impl/issue-<N>-<short-desc> origin/main
```

**Any other repo**:

```bash
git checkout main && git pull
git checkout -b impl/issue-<N>-<short-desc>
```

Never push directly to main. Branch naming: `impl/issue-N-desc` (implementation), `fix/desc` (fix), `refactor/desc` (refactor), `design/...` (handled by `/spec --design`).

Pick the lowest-numbered unblocked issue if several are available.

### 3. Implement

- For a well-scoped issue, dispatch a `general-purpose` subagent with `isolation: "worktree"`. Give it the full issue text and the repo's conventions, since it sees none of your context. Tell it to: stay within the issue's files (report back rather than grow past ~15 files or ~400 changed lines); add no dependencies the issue doesn't call for; run the repo's tests, linter, formatter, and type checker; add the tests the issue calls for; leave no debug code; commit without AI-attribution trailers; and **never push, open a PR, or touch any other clone**. It returns the diff and the gate results to you. Implement inline when the change is small or needs back-and-forth with the user.
- Follow the issue spec exactly — no scope creep
- Grep for existing patterns before writing new code
- Write tests alongside code, not after
- Keep commits atomic; **no Co-Authored-By or other AI-attribution trailers**

**Do NOT**: add features not in the issue, refactor unrelated code, change established patterns without discussion, skip tests for "simple" code.

### 4. Pre-PR Verification

Don't open the PR until checks pass — the test plan reflects completed checks, not TODOs.

- Automated tests for the changed code
- Build verification if build config/dependencies changed
- Manual smoke test if runtime behavior changed
- If a skill/hook/tool was added or modified, invoke it and confirm it works

Fix failures before creating the PR. Note N/A items explicitly.

### 5. PR

```bash
gh pr create --title "[Impl] #<N> - <description>" --body "..."
```

Body: summary (1-2 sentences), changes (file: what changed), test plan (checked items only), `Closes #<N>`.
Labels: `implementation`.

**External repos** (anything the user doesn't own): draft the full PR body and show it to them for preview. Hard stop — do not run `gh pr create` until they confirm.

### 6. Review

Structurally enforced — invoke via the Skill tool immediately after PR creation. Skip only for a fast-lane change on `trellis` / `trellis-cron` (say which lane in the PR body).

- Branch `design/*` → Skill `design-review` with `--comment <PR>` (add `--detailed` for an LLD)
- Everything else → Skill `code-review` with `--comment <PR>`
- `--deep` only when the user explicitly asks for it

Use the Skill tool directly — don't just describe doing it.

### 7. Address Feedback

- Fix only issues that survived validation, not filtered false positives
- Push the revision to the same branch
- Max 2 review passes — after the second, hand to the user regardless

### Definition of Done

- [ ] Issue created (or exception noted)
- [ ] All issue requirements implemented
- [ ] Pre-PR verification completed
- [ ] Tests pass
- [ ] No new linting errors
- [ ] Review cycle completed (N/A for a fast-lane change on `trellis` / `trellis-cron`)
- [ ] Merge: on `trellis` / `trellis-cron`, find the change's lane in the **Merging** paragraph of `AGENTS.md`. Fast lane, or reviewed lane with findings fixed: merge it yourself. Remove the worktree first (`git -C ~/projects/<repo> worktree remove ~/projects/.worktrees/<repo>-<slug>`), since a branch that is checked out can't be deleted, then run `gh pr merge <N> --merge --delete-branch`. The user's lane, or a self-originated change outside the fast lane: leave it open and tell them why, unless the user said in this session to merge this specific PR after review. Then quote them in the PR body and merge. If a calling skill sets a stricter rule, the stricter rule wins. On any other repo, hand to the user for merge.
- [ ] After a merge on `trellis` / `trellis-cron`: `git -C ~/projects/<repo> pull --ff-only` in the main clone; on `trellis`, also tell the running sessions (`ListAgents`) the PR, a one-line summary, and whether to relaunch (see **Agent changes** in `AGENTS.md`). Their worktrees catch up to `main` on their next start.
- [ ] Issue auto-closed via PR merge

**Start from step 1 and proceed without prompting at each step unless blocked.**
