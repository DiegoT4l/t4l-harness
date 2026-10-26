---
name: correct
description: Find the mistakes agents keep repeating in this repository and make each one impossible, at the highest level that works (architecture, types, lint, test, docs last). Use when the user types /t4l:correct, or says they have corrected the same thing more than once.
disable-model-invocation: true
---

# t4l correct

The user keeps correcting agents for the same mistakes. Change the repository so the next agent cannot make them. Writing a longer instruction does not count: nothing fails when an agent skips a doc.

Assume every future contributor is an agent that sees only the files it opened, copies the nearest example, and takes the shortest path that compiles. Make a change that looks right from one file be right for the whole repo.

## 1. Find the mistake classes

Read, in this order, stopping when the evidence is enough:

- The corrections in this conversation.
- Recent commits, reverts and fixup commits (`git log --oneline -50`, `git log --grep='revert\|fix'`).
- Review comments on recent PRs (`gh pr list --state merged --limit 10`, then their comments) when `gh` is available.
- The repo's agent instruction files and comments that explain workarounds.
- Engram: search for earlier corrections and conventions for this project.

Group them into classes. A class counts once it has happened twice. Report each class with its evidence (commit, comment or quote). Do not invent classes from a single occurrence.

## 2. Fix each class at the highest level that works

1. **Eliminate it with architecture.** One owner per piece of state, one supported way per task. Hide internals so the wrong import fails to compile. Replace hand-synced lists with one source of truth. Delete the old way and the dead code an agent would copy.
2. **Enforce it with types.** Make the bad state unrepresentable. If bad code still compiles, add a lint or CI check whose error message names the file, type or function to use instead. If the pattern is already common, fail only when a change adds more of it.
   - Go: `depguard`, `forbidigo`, custom `go vet` analyzers, internal packages, unexported types, an architecture test that parses imports.
   - TypeScript: ESLint `no-restricted-imports` and `no-restricted-syntax`, `strict` flags, branded types, `dependency-cruiser`, a codemod plus a CI check.
3. **Test the behavior.** Fix or delete any test that still passes when the behavior it checks breaks, or that fails when only internals change.
4. **Hook it.** If it must hold during the session, not just in CI, add it to the repo's `verify` or `quick` command in `.t4l/config`, so the harness runs it and the agent cannot skip it.
5. **Write docs or rules last, and only for judgment calls** that no tool can check.

For each class, state the level you chose and why a higher one did not work.

## 3. Prove each check

A check that never failed proves nothing. For every new lint, test or hook:

1. Reproduce a real past mistake from the evidence (revert to the offending commit or recreate the pattern in a scratch change).
2. Run the check and show that it fails, with an error that names the fix.
3. Apply the fix and show that it passes.

Run the same command locally and in CI. Exceptions go on the offending line with a reason, an expiry date and a human's approval.

## 4. Keep the rule table

Keep a table in the repo's agent instruction file (`CLAUDE.md`, or `AGENTS.md` if there is no `CLAUDE.md`), under a heading `Rules and enforcers`:

| Rule | Enforced by | Level |
|---|---|---|
| <what must hold> | <command, lint rule, test, or "judgment"> | architecture / types / lint / test / hook / doc |

When the user corrects you later: fix the mistake and add the rule. If the rule is already in the table and nothing enforced it, that is a repeat: move it up a level in the same change. Drop a rule once its enforcer makes it impossible to break.

Do one commit per class. Do not commit without the user asking.

## Reply format

- Each class with its evidence.
- The level chosen and why a higher level was not possible.
- The failing-then-passing output of each new check.
- The updated rule table.
