# Playbook: refactor

A behavior-preserving change to structure or shape. Default mode: ODD + TDD with characterization tests. If it fails the resume test (many modules, several sessions), run it through the `feature` playbook with the specs stating "behavior unchanged".

The deliverable is the same behavior with less code. If the refactor adds more than it removes, say why.

## Steps

1. **State the invariant** in one sentence: what must not change (outputs, exit codes, public API, persisted formats).
2. **Pin today's behavior first.** For every entry point that goes through the code to be changed, make sure a test pins its current behavior, including edge inputs. Where none exists, write a characterization test and watch it pass on the old code. Commit these tests before the change when commits are authorized.
3. **Take the baseline.** Note the base ref (`HEAD` before you start). The regression script compares against it.
4. **Subtract before you add.** Remove dead code, redundant validators and stale stubs first, then reshape on the simpler base.
5. **Change in small verifiable steps.** After each step the tests are green. Keep each step reviewable (~400 changed lines at most).
6. **Migrate callers and delete the old API in the same change.** No compatibility layer that nobody calls.
7. **Regression check.** Run `t4l-regress.sh` with every entry point and `{edge}` for free-text commands, against the base ref. Every difference is a failure of the invariant: fix it, or stop and ask if the user wants the new behavior.
8. **Verify** with the repo's `verify` command.

## Reply format

- The invariant and the evidence that it held (`Regression:` line plus the key output in a code block).
- What was removed and what was added (lines).
- Anything that changed on purpose, and who asked for it.
