---
name: init-project
description: "Create a new project (domain) in the knowledge repo, or change an existing project's scope: align on scope and how the agent should behave there, seed it from context already in the knowledge base, and wire it into the memory index. Use when the user says 'new project', 'let's track X as its own area', 'widen X to cover Y', or /init-project. Not for adding facts or threads to an existing project; that's a normal doc update."
argument-hint: "<project name or area>"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# /init-project

Projects and domains are the same thing. Each project has one living doc,
`trellis-knowledge/projects/<p>.md`, plus cold docs in `docs/<p>/`. New knowledge goes into an
existing project unless the user names a new one, so this skill runs when they ask for one, or to
widen an existing one.

## 1. Check the map

- List `projects/*.md` and their Purpose lines. If an existing project already covers the area, the move is to widen that one, not to make a twin. Say so and confirm before writing anything.
- **Propose a split where it helps.** An area that keeps long-running records or needs its own behavior rules earns its own project; a catch-all personal project, for instance, may spin out a dedicated project with its own records and rigor once it grows enough distinct material.
- Blending across domains doesn't need a merged project. It happens in `memory/user_now.md`, which every session reads, and through cross-links.

## 2. Align (questions)

Ask 2–4 questions with `AskUserQuestion`, each with a recommended default:
- **Scope:** what's in, what's out, and where the line sits with each neighboring project.
- **Behavior:** how the agent should act in this domain. What role it plays (coach, analyst, admin), what rigor it applies, what it must never do.
- **Where the work happens:** here, another Claude surface, or both, and how decisions made elsewhere flow back in.
- **The name.** Offer 2–3 alternatives if the obvious one is fuzzy.

## 3. Seed from what's already known

The goal is a project that starts with context, not an empty template. Search the knowledge repo:
- `docs/manifest.json` first, then grep the docs, `memory/`, the other `projects/*.md`, and any prior exports under `docs/self-improve/`.
- For a big sweep, start an `Explore` subagent (read-only) and have it return file paths with excerpts. Read the important files yourself before writing them into the seed.

Write the seed carefully:
- Keep every fact's date and source.
- Mark anything that came from an export or an old doc as *unconfirmed*.
- **Never upgrade an old fact into current state without checking it with the user** (invariant 5).
- If sources contradict each other, list both and ask.

## 4. Write the project

`projects/<p>.md`, in the same structure as the other projects:
- `# <p>` and `**Last updated:**`
- `## Purpose`: one paragraph, including what's out of scope and where it goes instead.
- `## Current state`: the seeded facts, dated, with *unconfirmed* marks.
- `## Open threads`: what's pending, with deadlines bolded.
- `## How I think about this domain`: the behavior rules from alignment. Link the feedback memories that apply, and don't restate them.
- `## Key decisions and cold docs`: the creation decision, quoting the user's words, plus the sources.

Then wire it in:
- Add a line under `## Projects` in `memory/MEMORY.md`. Keep the index terse.
- If the domain changes how the user is doing overall, update `memory/user_now.md`.
- If a neighboring project's Purpose overlaps, move the shared material into one place and link the other to it.
- Personal or sensitive data stays out of anything public: it never goes in a public repo, the publish-template export manifest, or an outward message.

## 5. Commit and announce

- Commit only your own paths straight to main in the knowledge repo, then push with `scripts/kb-push`. The knowledge repo is never reviewed.
- Tell the running sessions the project exists and how it touches them; `ListAgents` shows who's running. If there's real domain work waiting, hand it to whichever session owns that work, in a doc and a message.
- If the project should have a skill or a scheduled job, suggest `/skill-builder` or `/cron-builder` rather than building it here.
</content>
