---
name: research
description: "Execute structured research — a quick inline lookup, a deep multi-agent dig, or a full staged sprint with persistent artifacts. Use when the user says 'research X', 'deep dive on X', 'research sprint on X', or a topic needs multi-source investigation."
argument-hint: "<topic or question>"
allowed-tools: Skill(update-state *), Read, Write, Glob, Grep, Bash, WebFetch, WebSearch, Agent
---

# /research

## Tier selection

| Tier | Method | When |
|---|---|---|
| Quick | Direct web search | 1-2 facts, simple lookup |
| Medium | Search + page fetches | <5 sources, manageable context |
| Deep | Parallel `researcher` agents | 3+ independent sub-questions, 5+ sources |
| Sprint | Staged multi-agent plan (below) | Comprehensive coverage, feeds a real decision, or builds lasting reference |

Decision: can you answer in 1-2 searches → Quick. Need a few pages but context stays light → Medium. Would bloat context or has 3+ independent sub-questions → Deep (one `researcher` dispatch per sub-question, launched in parallel, each with an output tier and a scoped question). Needs breadth and depth together → Sprint.

For a multi-file debugging question instead of a research one, dispatch `general-purpose`, not `researcher`. Tell it to state hypotheses before searching; check environment, config, and git history (`git log -S`, `git blame`) before reading code; cap itself at about 10 file reads; and return the root cause with a confidence level, the evidence, the hypotheses it ruled out, and the smallest check that would prove the cause. It's read-only unless you say otherwise.

**Dispatching `researcher`**: give it a scoped sub-question (not the whole topic), an output tier — brief (~500 tok, 1-3 facts), standard (~1500 tok, most tasks), or detailed (~3000 tok, sprint sub-tasks) — and, if relevant, a preferred format (structured/table/bullets). It routes to the right source itself (see `agents/researcher.md`) and falls back to web search if an MCP source is down. It sees none of your memory — carry over anything it needs.

---

## Research Sprint

Use for a topic that needs multiple sources across sub-domains, has independent sub-questions, or feeds a downstream decision. Every sprint starts with Stage 0 — never skip it, even if the topic looks simple.

### Stage 0: Architecture

**1. Topology** — name the shape of the research (blend or invent as needed):

| Pattern | When |
|---|---|
| Entity Sweep | Standardized data across N entities (e.g. a metric for a list of items) |
| Thesis Construction | Argued bull/bear cases per subject, cross-referenced |
| Landscape Map | Chart an unfamiliar space, parallel by angle then synthesize |
| Feasibility Study | Can X be done under constraints Y — sequential, each finding constrains the next |
| Comparative Analysis | N options against decision criteria |
| Deep Dive | One subject, sequential depth, branch on findings |

State it: "This is a [pattern] because [reasoning]. Stages: [...]."

**2. Staging plan** — for each stage: objective, method (parallel `researcher` dispatch / sequential dig / synthesis pass), inputs from prior stages, gate criteria (good enough to advance?), and what happens if it underdelivers (retry a different angle, proceed with a noted gap, or stop and ask). Not every sprint needs every stage type; a simple entity sweep might be collect → cross-reference → synthesize.

**3. Source strategy** — for this specific topic, what's primary (ground truth: filings, papers, official docs, benchmark results), analytical (expert commentary, lab blogs, analyst reports), community (forums, Q&A sites — practitioner signal, not fact), and what to avoid (SEO farms, stale pages, conflicted sources). `researcher` already knows domain routing — this is about weighting for this topic, not re-listing tools.

**4. Output design** — shape the deliverable to what it feeds: a human decision (ranked options, trade-offs, decision matrix), a follow-on sprint (structured data, uncertainty map), or a terminal reference (executive summary + findings + recommendations + open questions). Always close with **Open Questions & Flags**.

**5. Documentation plan** — decide which intermediate artifacts have standalone value (reusable, updatable, or needed for verification) versus which are disposable (raw search dumps, superseded drafts, anything fully captured in the final synthesis). State it: "Persistent artifacts: 1. [name] — [contents] — [why]. ... Final synthesis: `_synthesis.md`."

### Checkpoints

Three checkpoints, Interrupt & Resume unless noted — blocking by default. The user can say "skip checkpoints" for a re-run with known-good parameters, or "quick" for a trivial case.

1. **Pre-research alignment** — after Stage 0, before any agent launches. Show the topology, staging plan, source strategy, output design, and artifact plan; ask for adjustments and approval to proceed.
2. **Mid-research direction check** (Human-as-a-Tool, non-blocking) — after initial findings land, before deep dives. Share 2-3 key findings plus anything unexpected, ask 2-4 targeted questions (pivot? prioritize depth vs breadth? scope creep?). Skip with a note if findings clearly confirm the plan.
3. **Pre-synthesis validation** — after all stages complete, before writing the synthesis. Summarize evidence and the planned synthesis shape; confirm it answers the actual question before committing to the write-up.

Record each outcome (approved / approved-with-edits / pivoted / skipped, with notes) in `_architecture.md`.

### Execution

- Track stage progress with your task list so a multi-stage sprint doesn't lose state mid-way.
- Launch parallel `researcher` agents in a single message, 2-4 per stage — each with a clearly scoped, non-overlapping question and an output tier. Pass `model: "sonnet"` on sprint dispatches if `researcher` defaults to a lighter model: sprint sub-tasks carry the heavy synthesis and source grading that need the stronger model. More than 4 adds coordination overhead without proportional benefit.
- Adaptive depth: go deeper where findings are rich or contradictory, lighter where they're settled. If a stage reveals the topology itself was wrong, stop and re-architect — note the pivot and why.
- Between stages, check: did this stage produce what the next one needs? Any gap that would undermine downstream stages? If a gate fails, retry with a different angle or proceed with the gap explicitly noted.

### Output & synthesis contract

Pick the project the topic belongs to (one of the domains set up via `/init-project`; default to a general `research` project if none fits) and write to:

```
~/projects/trellis-knowledge/docs/<project>/<YYYY-MM-DD>_<sprint-name>/
  _synthesis.md         ← final deliverable, always present
  _architecture.md       ← Stage 0 output + checkpoint outcomes, always present
  <artifact-name>.md     ← persistent intermediate artifacts, self-describing names
```

`_architecture.md` holds the topology, staging plan, source strategy, documentation plan, and the checkpoint outcomes table — cheap to keep, useful when revisiting weeks later. `_synthesis.md` should reference artifacts by filename ("see `profile.md` for the full evidence chain") rather than inlining everything. Don't persist raw search dumps, superseded drafts, or anything the synthesis already fully captures.

Close out: update `projects/<project>.md` (Current state / Open threads / Last updated, and a pointer to the new synthesis under Key decisions and cold docs), then run `/update-state`.
