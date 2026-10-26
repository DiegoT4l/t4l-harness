# Feature document template

Create at `.t4l/tasks/<feature-name>.md`. Subagents read it by reference, in this order, and stop at `## Log`.

```markdown
# <feature-name>

Mode: <ODD only | ODD + TDD | ODD + SDD>   Lane: large

## Specs

S1. <behavior>. Quote the user's exact strings, error messages and examples verbatim.
    Acceptance: <observable criterion>
    Check: <command or procedure that proves it>
    Existing behavior at risk: <entry points and inputs that work today and might change, or `none` and why>

S2. ...

<!-- SDD only: add scenarios below each spec -->
    Scenario: <name>
      Given <state>
      When <action>
      Then <measurable outcome>

## Tasks

| ID | Spec | Status | Deps | Files | Commit |
|----|------|--------|------|-------|--------|
| T1 | S1   | todo   | -    | src/** | -      |

## Log

L1. <the user's original request, verbatim>
L2. <later correction, evidence or rationale, appended in order>
```

`scripts/t4l-task.sh` creates this document and edits the Tasks table; `.t4l/state` holds the machine state (feature, mode, gate, phase) that the hook `guard` reads. Status is one of `todo`, `doing`, `review`, `done`. `Files` are globs the task may touch (`-` when not declared). `Deps` are task IDs that must be `done` first.

Rules:
- A requirement change rewrites only the affected spec and reopens only its tasks, with a reason in the log.
- A task is checked off only with observed proof, and its commit is recorded.
- Mirror the whole document to Engram under topic `t4l/<feature>/tasks` after every material change, then read it back.
- Add `.t4l/` to `.gitignore` if it is not there.
