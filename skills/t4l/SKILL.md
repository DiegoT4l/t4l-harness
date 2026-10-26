---
name: t4l
description: Router for engineering tasks. Authorizes, explores, classifies a request as read-only, small or large, picks the method (ODD only, ODD + TDD, ODD + SDD) and the playbook. Use at the start of any request to change code, fix a bug, build a feature, investigate, or when the user types /t4l or asks to force a mode ("use SDD", "no TDD").
---

# t4l router

The kernel (`rules/t4l.md`) holds the always-on rules. This skill is the procedure to follow at the start of a task. If the kernel is not loaded in this session, read it first.

## 1. Authorize

Decide whether the request asks for a change.

- No change asked (question, explanation, review, proposal): use the **investigate** playbook and stop there. Write nothing.
- Change asked: continue.

## 2. Explore, proportionately

Read what you need to understand the task, within the kernel's evidence budget. If understanding needs more, send one read-only explorer and re-classify with its report.

Resolve uncertainty only where it matters:
- A fact you can observe: run it.
- A real product decision: ask one question, then wait. If there are several unspecified decisions, or you would have to invent behavior (flags, defaults, error contracts, edge cases), do not pick silently: that is the SDD signal (section 4).
- A high-consequence premise nobody has verified: one independent read-only challenge.

## 3. Classify

Apply the resume test: could someone resume this from the request plus `git diff`, with contained risk?

| Result | Lane | What it means |
|---|---|---|
| Yes | **small** | Inline. No subagents. No task document. Proportionate checks. |
| No | **large** | One feature document in `.t4l/tasks/<feature>.md`, mirrored to Engram before the first source write. Tell the user in one line which document was created and how many tasks it holds. |

Do not classify by file count or because a todo list was requested.

## 4. Pick the method

Start with the cheapest mode that fits. Escalate only on a signal.

| Mode | Pick it when | Procedure |
|---|---|---|
| **ODD only** | Small understood change, config, docs, scripts, perf, mechanical migration, or no runnable test is reasonable | Implement, run the checks the change deserves, regression check if shared code changed (section 7), report. |
| **ODD + TDD** | Observable behavior and a deterministic, runnable test: bugs with a repro, bounded new logic, refactors | RED observed, then minimal GREEN, then REFACTOR with the bar green. One test at a time. For a refactor, write characterization tests first. Then the regression check (section 7). |
| **ODD + SDD** | Ambiguous behavior, behavior you would have to invent, public API or CLI surface, real product decisions, work crossing modules or services, work another session will resume | Write specs, get approval (gate in section 6), then TDD per scenario, then the regression check (section 7). |

Rules:
1. SDD implies TDD. TDD does not imply SDD. ODD is always underneath.
2. Size does not decide the mode. A small public-API change may need SDD; a large mechanical rename may need ODD only plus a regression check.
3. Escalation signals: ambiguous spec, behavior you would have to invent, two failed fixes sharing one premise, high risk, the user asked for approval.
4. Declare the choice in one line, for example `ODD + TDD: bug with deterministic repro`. Put it in the feature document when one exists.
5. The user can force a mode ("use SDD", "no TDD"). Obey, and say what that costs if relevant.
6. If TDD was chosen but no runnable deterministic test exists, say so, fall back to ODD only and run proportionate functional checks.
7. A new flag, option, command, endpoint or exported function with unspecified details is SDD, even when the change is small. Do not state your assumptions and proceed: list them as specs and ask.

## 5. Pick the playbook

| Task | Playbook | Default mode |
|---|---|---|
| Explain, investigate, review, propose | `playbooks/investigate.md` | none (read-only) |
| Bug with a deterministic repro | `playbooks/bug.md` | ODD + TDD |
| Bug without a repro yet | `playbooks/bug.md`, reproduce step | ODD only until reproduced, then TDD |
| Anything else | no playbook yet: apply the kernel and the mode procedure above | per section 4 |

Related skills: `/t4l:init` enables the verification hooks in a repo; `/t4l:correct` turns repeated corrections into enforced structure. Playbooks for feature, refactor, perf, ship, babysit and pickup are planned (see `docs/design.md`).

## 6. Large lane (v0.1)

Create `.t4l/tasks/<feature>.md` from `references/feature-doc.md`. In v0.1 the lead implements inline; dedicated `implementer`, `judge` and `reviewer` agents arrive in v0.3.

- Specs quote the user's exact strings, error messages and examples verbatim.
- `L1` in the log is the original request, verbatim. Later corrections and evidence are appended.
- A requirement change rewrites only the affected specs and reopens only their tasks.
- Mirror the document to Engram under topic `t4l/<feature>/tasks`, then read it back: the two writes are not atomic.
- Check a task off only with observed proof.
- Commit in reviewable units of about 400 changed lines, tests and docs alongside the behavior, Conventional Commit messages. The 400 is a planning heuristic: never split artificially or delete comments and blank lines to hit it.

### Approval gate (SDD only)

After the specs are written, stop and ask the user to approve or change them. Do not write production code before approval. In ODD + TDD and ODD only there is no gate.

**Inline SDD (small lane).** When the resume test says small, skip the task document and the Engram mirror. Write the specs in the reply:

```
S1. <behavior, with the exact input and output>
    Scenario: <name>  Given <state> / When <action> / Then <measurable outcome>
S2. ...
Existing behavior at risk: <entry points and inputs that work today and might change: commands, flags, parsing, text that looks like an option, empty input>
Assumptions I need confirmed: <each decision the user did not specify, with the default you propose>
```

`Existing behavior at risk` is mandatory: answer it by reading the code that the change will touch, and list the inputs you will compare in the regression check. If nothing is at risk, write `none` and say why. Keep it to a handful of specs, stop, and wait. After approval, run TDD per scenario, one `S#` at a time, and map each `S#` to its test in the final report. An approved inline spec that grows beyond the resume test is promoted to the large lane.

## 7. Regression check

Run this before closing any change that touches code shared with other entry points (functions, flags, parsing, config, an exported API). Skip it for isolated new files and docs.

1. List the existing entry points that go through the changed code: CLI commands and flags, endpoints, exported functions. Start from the `Existing behavior at risk` line of the specs when there is one.
2. Write one command per line for each, with representative inputs, and pipe them to the script. Use `{edge}` wherever a command takes free text: it expands to empty, option-like (`-a-`, `--lead`, `-`, `--`), unicode, padded and quoted inputs, so the inputs most likely to break are always tried:

   ```bash
   sh "$T4L_ROOT/scripts/t4l-regress.sh" <<'EOF'
   go run ./cmd/slug "Hello, World!"
   go run ./cmd/slug {edge}
   go run ./cmd/slug
   EOF
   ```

   Use the path from the `T4L_ROOT=` line that the SessionStart hook prints at the top of the session context (it is not a shell variable). If it is missing, use `../../scripts/t4l-regress.sh` relative to this skill's directory. It runs each command on a clean checkout of `HEAD` (the previous code) and on the working tree, compares stdout, stderr and exit code, and prints only the differences. Use `--base <ref>` when the previous code is not `HEAD` (for example, after committing part of the work); `--timeout SEC` for slow commands.
3. Re-run the full list after the last code change. Read each `DIFF`. A difference the user asked for is expected: keep the command in the run and list the difference in the report. A difference nobody asked for is a regression: fix it, or if it is a product decision, stop and ask. Pin the previous behavior with a test either way.
4. An entry point with no test gets one for its previous behavior before you change it, not after.

## 8. Close

If `.t4l/config` exists, the Stop hook runs the repo's `verify` command when the tree has changes; treat its failure as a failed check, not noise. Report the verified outcome, every failed or pending check, and the next step. Show the RED and GREEN evidence in a code block (failing test names, final pass line, the real command's output). End the report with the regression line, exactly one of:

- `Regression: <N> entry points compared against <ref>; no unrequested differences.`
- `Regression: <differences found and what was done about each>.`
- `Regression: n/a (<reason, for example docs only or isolated new file>)`.

A report for a change to shared code without that line is incomplete. Follow the reply format of the playbook when one applies. Save decisions and non-obvious findings to Engram.
