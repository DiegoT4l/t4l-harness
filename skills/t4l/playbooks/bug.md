# Playbook: bug

Default mode: ODD + TDD once a deterministic repro exists. Until then: ODD only.

Be scientific. Every shipped line traces to runtime evidence. A "might help" guard is a hypothesis, not a fix. When evidence refutes a hypothesis, revert whatever it motivated. Ship the smallest change the evidence justifies.

## Steps

1. **Reproduce it yourself**, on the same surface the user hit (CLI, HTTP endpoint, UI, test). Ask the user only with a specific reason the surface cannot be reached, and only after driving it as far as it goes. If it will not reproduce, tighten the conditions (data, timing, environment) before giving up, and say what you tried.
2. **Find the root cause by elimination.** Seed the hypotheses with the code involved (`t4l-search.sh` for the behavior, when ccc is enabled). List candidate hypotheses and rule them out one at a time, each pass taking the split that removes the most remaining space. Use runtime evidence: logs, debugger output, added instrumentation. When state is unclear, instrument and read it back; do not infer.
   - Use history (`git log -S`, `git bisect`) to find when it broke.
   - If two fixes that share one premise have failed the same check, write the premise down and test it directly before a third attempt.
3. **Write the failing test** that captures the bug, through the public interface, and observe it fail for the right reason. If no cheap deterministic test exists, say so and use the repro itself as the check.
4. **Fix at the first place the system went wrong**, not where the symptom shows. No guards for states that should not exist.
5. **Verify on the same surface**: the original repro now passes and the new test is green. "Inconclusive" or a different surface is not a pass; flag it. Then run the existing checks for the touched area and the regression check (router section 7): the fix must not change any behavior nobody asked to change.
6. **Stage commits** so the failing test lands before the fix when the history is meant to be read, and keep each unit small. Conventional Commit messages.

## Language-specific checks

- **Go**: `go test ./...` on the touched packages, plus `go vet`. For races, `go test -race` on the affected package. Use the `cc-skills-golang` skills (`golang-troubleshooting`, `golang-safety`, `golang-testing`) when the bug involves panics, nil safety, concurrency or test design.
- **TypeScript**: the repo's `test` and `lint` scripts (detect pnpm, npm or bun from the lockfile) and `tsc --noEmit` if there is a typecheck script.

## Reply format

- What was broken.
- Root cause, with the evidence that proves it.
- The fix and why it lives there.
- How you verified it: the failing test names and the final pass line in a code block, plus the output of the original repro before and after.
- Anything left unverified.

Save the root cause to Engram when it was non-obvious.
