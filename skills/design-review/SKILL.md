---
name: design-review
description: "Design review a pull request for architectural fit, feasibility, and completeness. Supports --comment to post to GitHub and --detailed for LLD-depth analysis."
allowed-tools: Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh pr comment:*), Bash(gh api:*), Read, Glob, Grep, Agent
---

# Design Review Skill

Multi-agent design review for design-doc PRs: architectural fit, feasibility, and implementation readiness.

**`trellis-knowledge` is never the target of a PR or a review.** Self-design docs about the agent itself are committed straight to `trellis-knowledge` main — if asked to review one there, say so and stop.

## Usage

```bash
/design-review <PR_NUMBER>                       # Standard (HLD-appropriate)
/design-review --detailed <PR_NUMBER>             # Detailed (LLD-appropriate)
/design-review --comment <PR_NUMBER>              # Post results as PR comment
/design-review --comment --detailed <PR_NUMBER>   # Both
```

## Model Usage

- **Haiku**: pre-check, context gathering, summarization
- **Sonnet**: all review and validation agents

**Reviewer subagents see none of the orchestrator's context.** Every dispatch prompt must be self-contained: quote the design doc's own stated problem/goals, the diff, and any relevant repo conventions (AGENTS.md/CLAUDE.md text) directly in the prompt — don't just hand over a path and assume it'll be read the same way.

## Standard Review (6 steps)

**Step 1: Pre-Check (Haiku)**
Skip if the PR is closed, draft, or already has a "Design Review" comment. Detect doc type (HLD/LLD) from the PR title and files changed.

**Step 2: Gather Context (Haiku)**
- Read the design doc's own stated problem/goals section (this replaces milestone lookup — there's no milestone tracking; the doc's own scope is the source of truth)
- Read `skills/spec/SKILL.md` § Mode: Design Spec for process expectations
- If reviewing an LLD: read the corresponding base design doc it extends (same repo, referenced from the LLD file) for consistency
- Read the target repo's root AGENTS.md/CLAUDE.md if architectural conventions are relevant

**Step 3: Summarize PR (Haiku)**
PR title, description, doc type (HLD/LLD), files changed, and the design's stated goals.

**Step 4: Parallel Review (5 Sonnet agents)**

**Agent 1 — Scope Alignment**
Does the design address the problem/goals it states for itself (and the original request/issue, if given)? Are out-of-scope items called out? Are success criteria achievable with this design? Are dependencies acknowledged and realistic?

**Agent 2 — Architectural Fit**
Follows established patterns? (Grep to verify pattern claims.) Unnecessary complexity? Cross-cutting concerns (logging, error handling, auth) addressed? Integration points with existing systems clearly defined?

**Agent 3 — Feasibility & Risk**
Can each component be built as described? Failure modes at system interfaces identified? Dependencies realistic and available? Risk mitigations specific, not generic ("monitor closely")?

**Agent 4 — Alternative Analysis**
Why this approach over alternatives? Trade-offs explicit? Rationale given for major decisions? Are obvious alternatives mentioned and evaluated?

**Agent 5 — Communication Quality**
Understandable in a 2-minute skim? Progressive disclosure (summary → details)? Prose for reasoning, diagrams for relationships? Detail level appropriate for doc type? Code is design-level (interfaces/pseudocode), not runnable? Within length guidelines (HLD 6-10 pages, LLD 15-25)?

**High-signal guidance (all agents)**

DO flag: scope contradictions against the doc's own stated goals, inconsistent patterns (claims X, grep shows different usage), feasibility gaps, missing rationale, unaddressed risks at integration points, implementation-level (copy-pasteable) code, excessive length, unreadable structure (no summary, buried decisions).

Do NOT flag: typos/grammar (unless they hurt clarity), personal style, diagramming tool choice, nitpicks that don't affect soundness or communication.

**Step 5: Validate Findings (parallel Sonnet agents)**

One validation agent per finding: verify against the doc's stated scope, grep for claimed patterns, check the base doc if this is an LLD, confirm the finding is factual not opinion. Return VALID or INVALID with reasoning.

**Step 6: Filter and Output**

Keep only VALID findings:

```markdown
## Design Review

Found N finding(s):

### 1. [Brief title]
**Section**: [design doc section]
**Category**: Scope | Architecture | Feasibility | Alternatives | Communication Quality
**Severity**: Critical | Significant | Minor
**Description**: [...]
**Question**: [senior-engineer framing]
**Suggestion**: [actionable recommendation]
```

If `--comment`: post via `gh pr comment`.

### Severity

**Critical** (blocks approval): unreadable doc, no alternatives considered for major decisions, audience can't understand key decisions, no diagram where one's needed.
**Significant** (fix before merge): excessive detail for doc type, missing non-goals, implementation-level code, missing rationale for a significant choice.
**Minor** (optional): diagram quality, prose concision, structure.

---

## Detailed Review (8 steps)

Standard Steps 1-5, then:

**Step 6: Expanded Analysis (2 Sonnet agents)**

**Agent 6 — Completeness & Decision Quality**
API contracts fully specified? Module structure detailed enough to generate issues from? Testing requirements defined per component? Alternatives and trade-offs explicit? Non-goals defined? Any gap that would block implementation?

**Agent 7 — Consistency with the base doc**
Does the LLD align with the HLD/base doc it extends? Are earlier decisions reflected correctly? Any contradiction with established architecture? Do references to existing code match the current implementation (grep to verify)?

**Step 7: Second Validation Pass**
Read the complete base doc and LLD side-by-side; grep the codebase for claimed implementation references.

**Step 8: Filter and Output**

Combine validated findings from Steps 5 and 7:

```markdown
## Design Review (Detailed)

Found N finding(s):

### 1. [Brief title]
**Section**: [...]
**Category**: Scope | Architecture | Feasibility | Alternatives | Communication Quality | Completeness | Consistency
**Severity**: Critical | Significant | Minor
**Description**: [...]
**Question**: [...]
**Suggestion**: [...]
```

If `--comment`: post via `gh pr comment`.

## Category Reference

- **Scope**: alignment with the design's own stated objectives and boundaries
- **Architecture**: pattern consistency, complexity, integration points
- **Feasibility**: buildability, dependencies, risk identification
- **Alternatives**: rationale, trade-off analysis
- **Communication Quality**: readability, detail level, visual clarity
- **Completeness** *(detailed only)*: implementation-readiness, specification detail
- **Consistency** *(detailed only)*: alignment with the base doc, codebase references

## Implementation Notes

- Launch all agents in a step simultaneously (one message, multiple Agent calls)
- Standard: ~7+ agents total (pre-check, context, summary, 5 review, N validation)
- Detailed: ~9+ agents (standard + 2 expanded + N validation)
- Each agent returns compressed findings to the orchestrator, not raw dumps

**Code review vs. design review**: code review asks "is this code correct, safe, maintainable?" against the codebase and repo conventions. Design review asks "should we build it this way?" against the design's own stated goals and sound architecture.

## Error Handling

- Design doc has no stated goals section: warn and proceed on the request/issue context alone
- Base doc not found (reviewing an LLD): flag as a critical Consistency finding
- Pre-check fails: report and exit, don't review
- Validation agents disagree: escalate to the user, don't auto-filter

## Examples

```bash
/design-review --comment 15
/design-review --comment --detailed 18
/design-review 15   # local, no GitHub comment
```
