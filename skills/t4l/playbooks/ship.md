# Playbook: ship

Turn finished, verified work into reviewable commits and, if the user asks, a pull request. Nothing is committed, pushed or opened without an explicit request from the user.

## Before you ship

1. **Verified.** The repo's `verify` command passes. For a large-lane feature, the judge report says `APPROVED` and `t4l-task.sh check` is clean.
2. **Regression.** The report has a `Regression:` line on the final code.
3. **Clean scope.** `git status` shows only files the work touched. Nothing from `.t4l/`, no scratch files, no secrets.

If any of these fails, stop and say which.

## Commits

1. **Branch.** If you are on the default branch, create a feature branch first. Never commit to `main` directly.
2. **Slices.** Group changes into reviewable commits of about 400 changed lines. Keep each coherent: behavior, its tests and its docs together. A high-risk item (auth, data loss, concurrency) gets its own commit. The 400 is a planning heuristic: do not split artificially.
3. **Order.** Where the history will be read, the failing test or the pinned behavior goes before the change that needs it. Dependencies go first.
4. **Messages.** Conventional Commits (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`), a subject that says what changed, a body that says why when it is not obvious.
5. **No attribution.** No co-author trailers and no mention of Claude, Claude Code or Anthropic or AI in any message.

After each commit, confirm the working tree builds and tests pass for that slice when it is cheap to do so.

## Pull request (only if the user asked)

1. Push the branch and open the PR with the forge CLI (`gh pr create`). Use the repo's PR template if one exists.
2. Title: a Conventional Commit style summary. Body, in this order:
   - **What and why**, in two or three sentences.
   - **How it was verified:** the commands and their key output (RED/GREEN lines, `Regression:` line), in code blocks.
   - **Risks and edge cases** the reviewer should look at.
   - **Open decisions** and anything deliberately left out.
   - **Slices:** which commit holds what, when the PR has more than one.
3. No attribution footer of any kind.

If the change exceeds the size heuristic by a lot, propose a stack of smaller PRs and ask before pushing.

## Reply format

- The commits created (hash and subject) and the branch.
- The PR URL if one was opened.
- What was left uncommitted or unpushed on purpose.
