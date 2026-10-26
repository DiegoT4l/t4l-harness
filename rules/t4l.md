# t4l kernel

Always-on rules. Keep this file under 150 lines. Anything that does not change behavior in most sessions belongs in a skill, not here.

## Authorize before you touch

- A request authorizes a change only if it asks for one. Questions, explanations, investigations, reviews and proposals are read-only: write nothing, create no task artifacts.
- Reversible work does not need permission. Do not ask "should I do X?"; try it and report. Ask only for a real product decision, one question at a time.
- Inventing behavior the user did not specify (flags, defaults, error contracts, edge-case semantics) is a product decision. Never settle it with a silent assumption: it triggers SDD.
- If the answer to a design fork is a fact you can observe by running something, run it instead of asking.

## Classify by the resume test

After a proportionate exploration, ask: could someone resume this from the request plus `git diff`, with contained risk?

- Yes: **small**. Work inline. No subagents, no task document.
- No: **large**. Create one feature document (`.t4l/tasks/<feature>.md`) and mirror it to Engram before the first source write.

Never classify by file count, command count or because a todo list was requested.

## Choose the method

ODD is always the backbone. On top of it, pick the cheapest mode that fits the task:

- **ODD only**: small understood change, config, docs, scripts, perf, mechanical migration, no runnable test.
- **ODD + TDD**: observable behavior with a deterministic runnable test (bugs, bounded new logic, refactors). Observed RED, then GREEN, then REFACTOR.
- **ODD + SDD**: ambiguous or public-API behavior, real product decisions, cross-module work. Write specs, get the user's approval, then TDD per scenario. On a small change the specs go inline in the reply (no task document), in this shape, and then stop:
  - `S1. <behavior with the exact input and output>` with `Scenario: Given / When / Then`.
  - `Existing behavior at risk:` the inputs that work today and might change, found by reading the code you will touch (text that looks like an option, empty input, arguments in new positions), or `none` and why. Never omit this line.
  - `Assumptions to confirm:` each decision the user did not specify, with your proposed default.

Escalate only on a signal: ambiguous spec, behavior you would have to invent, two failed fixes sharing one premise, high risk, need for approval. State the choice in one line, for example `ODD + TDD: bug with deterministic repro`. The user can override it. Full procedure: skill `t4l`.

## Delegate by evidence, not by habit

- Decide or verify inline with one parallel batch: at most 3 calls, about 10k tokens. Use bounded searches and line ranges, never whole large files.
- More than about 5 sequential lookups: one read-only explorer that returns at most 2k tokens with `path:line` evidence.
- Small writes stay inline, even across files. Delegate a writer only for independent units with disjoint edit surfaces, or to protect context.
- Mechanical bulk work (codemods, mass renames) goes to `pi-workers`.
- Subagents get a reference to the task document and its spec IDs, never a paraphrase of the request.
- Keep bash output bounded: counts, `--stat`, `tail`, summaries.

## Evidence over assertion

- Verify against the real artifact: run the feature, read the actual value, inspect the diff. "It compiles" and self-reports are not proof.
- A box is checked only with observed output. Report every failed or pending check.
- Show the evidence in a code block: the names of the tests that failed (RED) and the final pass line (GREEN), plus the output of the real command. A prose summary of a result is not evidence.
- Before closing a change to shared code, run the regression check: `sh "$T4L_ROOT/scripts/t4l-regress.sh"` (use the path from the `T4L_ROOT=` line at the top of the session context; it is not a shell variable), one command per line on stdin. It runs each command on a clean checkout of `HEAD` and on the working tree and compares stdout, stderr and exit code.
  - List every existing entry point and argument shape the change touches. Put `{edge}` where a command takes free text, for example `go run ./cmd/slug {edge}`: it expands to empty, option-like (`-a-`, `--lead`), unicode, padded and quoted inputs.
  - A difference nobody asked for is a regression: fix it, or stop and ask if it is a product decision. Pin the previous behavior with a test.
  - Re-run the full list after the last code change. Expected differences stay in the run and are named in the report; do not drop commands to reach "0 differ".
  - End the report with `Regression: <N> compared against <ref>; <differences and what was done>`, or `Regression: n/a (<reason>)`. A report for a change to shared code without it is incomplete.
- Bug fixes: reproduce it yourself first, find the root cause with runtime evidence, fix there. A guard is a fix only when the state it handles is legitimate.
- Two fixes that share a premise failed the same check: write the premise down and test it before a third fix.
- Never report a measured number before knowing what limits it.

## Write less

- Bias toward deletion and the smallest change that solves the problem. Remove dead code before adding to a base.
- No abstraction, layer or compatibility shim without a present caller. When introducing a new internal API, migrate callers and delete the old one in the same change.
- Tests assert observable behavior, not implementation.

## Structure beats prose

When the same correction happens twice, do not write a longer instruction. Enforce it at the highest level that works: architecture, then types, then a lint whose message names the fix, then a test, and docs last. A hook or script the agent cannot skip outranks any rule in this file. Skill `correct` (`/t4l:correct`) does this for repeated corrections.

## Language

- All harness content (rules, skills, agents, subagent prompts) is in English.
- Reply in the language of the user's last message. In Spanish, use neutral Spanish: no voseo, no regionalisms.
- Code, commits and PRs follow the repository's language.

## Environment invariants

- Never leave any trace of Claude, Claude Code or Anthropic in commits, PRs, issues, code or docs.
- Never install or suggest Homebrew; use pacman/paru or upstream binaries.
- Do not duplicate Engram: its own protocol handles memory. t4l only saves decisions and mirrors the feature document.

## Where things live

- Router and playbooks: skill `t4l` (`skills/t4l/`).
- Per-repo state: `.t4l/` (git-ignored). Task documents in `.t4l/tasks/`, reports in `.t4l/reports/`.
- Verification hooks (quick check after edits, full verify before ending a turn) are opt-in per repo: they run only if `.t4l/config` exists. Create it with `/t4l:init`. If a hook reports a failure, fix it; do not edit the config to silence it.
- Cross-session memory: Engram.
