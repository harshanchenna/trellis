---
name: spec
description: "Produce a durable spec artifact before doing the work. Three modes: --impl (GitHub issue), --design (design doc, PR if it's a code repo), --research (research brief that hands off to /research). Use when planning, designing, or creating an issue."
argument-hint: "[--impl|--design|--research] <description>"
allowed-tools: Skill(design-review *), Skill(research *)
---

## Overview

One entry point for "what kind of spec is this?" Every invocation produces a persistent artifact; the mode determines its type and where it lands.

## Mode Selection

| Signal | Mode | Output |
|--------|------|--------|
| `--impl` or "implement X", "fix X", "add feature X" | Implementation | GitHub issue |
| `--design` or "design X", "architecture for X" | Design | Design doc (+ PR if code repo) |
| `--research` or "research X", "investigate X" | Research | Research brief → feeds `/research` |
| Ambiguous | — | Ask: "Architecture design or implementation planning?" |

---

## Mode: Implementation Spec (`--impl`)

Produce a GitHub issue that's a self-contained implementation spec — anyone (or any model) should be able to implement from it alone.

1. **Explore context** — read relevant code, understand the problem
2. **Draft issue** using the template below
3. **Present to the user** for approval before publishing
4. **Publish**: `gh issue create --title "..." --body "..." [-R owner/repo]` (add `-R` if not run from inside the repo clone)

### Issue Template

```markdown
## Problem
[What problem does this solve?]

## Solution
[High-level approach]

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2

## Out of Scope
- [What this does NOT include]

## References
- Depends on: #issue-number (if any)
```

### Requirement Tracing (multi-task specs)

```
REQ-1: When the user submits the form, the system shall validate all fields.
TASK-1 (satisfies REQ-1): Implement form validation in FormValidator component.
```

### Linking

- Set dependencies: "Depends on #N" in References
- Labels: `implementation`, `bug`, `enhancement`, `refactor`

---

## Mode: Design Spec (`--design`)

1. **Determine target**:
   - **About the agent itself** (this agent's architecture, skills, memory, knowledge system) → write to `~/projects/trellis-knowledge/docs/self-improve/designs/{topic}.md`. Commit straight to `trellis-knowledge` main. **No PR, no review** — that repo never gets either.
   - **About a code repo** → write to `{repo}/docs/designs/{topic}.md`. Branch `design/{topic}`, open a PR, run `/design-review --comment <PR>`.
2. **Depth**: default to a single design doc (HLD-level). Only add an LLD if the user explicitly asks for one — write it as `{topic}-lld.md` alongside the base doc, referencing it, and run `/design-review --comment <PR> --detailed`.
3. **Research first** if the topic needs an evidence base — invoke `/research`, don't skip straight to designing on assumption.
4. **Write the doc** (see guidelines below).
5. **Present to the user** for approval.

### Design Doc Guidelines

- **Length**: 6-10 pages (HLD); LLD 15-25 pages max
- **Content**: component overview, integration points, technology choices with rationale, risks and mitigations. LLD adds: API contracts, module structure, testing requirements.
- **Diagrams**: system context, ASCII is fine
- **Audience**: understandable in a 2-minute skim — executive summary → details → appendices
- **Prose over bullets** for reasoning; code in the doc is interfaces/pseudocode only — if it could be copy-pasted into the codebase, it belongs in implementation, not the doc

### Skip the LLD when

Well-understood patterns (CRUD, CLI tools, scripts), solo implementer, or the HLD already gives enough clarity. Don't write an LLD that's just code in markdown.

### After a design doc is approved

Parse it into discrete implementation tasks, propose issues via `--impl` mode for each, get the user's approval, then create them.

---

## Mode: Research Spec (`--research`)

1. **Scope the need** — what questions need answering?
2. **Draft a brief**:

```markdown
## Research Brief: [Topic]

### Questions
1. [Specific question]

### Source Strategy
- Primary / analytical / community sources for each question

### Output Format
[What the deliverable looks like]

### Feeds Into
[Decision, design spec, implementation, or standalone knowledge]
```

3. **Present to the user** for alignment
4. **Invoke `/research`** with the brief as the dispatch prompt

---

## Frontmatter Convention

All spec artifacts:

```yaml
---
type: impl | design | research
topic: "brief-topic-slug"
date: YYYY-MM-DD
---
```

---

## Constraints (always active, not just when this skill runs)

- **Never push directly to main.** Code-repo work always goes branch → PR → review.
- **Every PR needs a corresponding issue** — exceptions: the user says "skip issue", it's a pure docs change, or it's a revert.
- **`trellis-knowledge` is never the target of a PR or a review.** If asked to `/pr` or review something there, say so and commit directly to main instead.
