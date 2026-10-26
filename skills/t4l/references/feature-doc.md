# Feature document template

Create at `.t4l/tasks/<feature-name>.md`. Subagents read it by reference, in this order, and stop at `## Log`.

```markdown
# <feature-name>

Mode: <ODD only | ODD + TDD | ODD + SDD>   Lane: large
Branch: <branch>   Delivery: <single PR | chained slices>   Status: <specs | approved | implementing | verifying | done>

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

| ID | Spec | Route | Status | Commit |
|----|------|-------|--------|--------|
| T1 | S1   | inline | todo  |        |

## Log

L1. <the user's original request, verbatim>
L2. <later correction, evidence or rationale, appended in order>
```

Rules:
- A requirement change rewrites only the affected spec and reopens only its tasks, with a reason in the log.
- A task is checked off only with observed proof, and its commit is recorded.
- Mirror the whole document to Engram under topic `t4l/<feature>/tasks` after every material change, then read it back.
- Add `.t4l/` to `.gitignore` if it is not there.
