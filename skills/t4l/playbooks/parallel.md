# Playbook: parallel (workflow-master)

For a large-lane feature whose tasks can proceed at the same time. The `t4l:workflow-master` runs the board: it launches implementers in isolated worktrees, keeps them from colliding or leaving their scope, integrates their branches on a separate branch and keeps slices within the size budget. You stay the owner of the plan and of the verdict.

## When to use it

- Two or more tasks with disjoint `Files` and no dependency between them, each worth several minutes of work. A subagent spends one to two minutes just reading, so tiny tasks do not pay back.
- Otherwise use the sequential `feature` playbook.

## Steps

1. **Plan for parallelism.** In the `feature` playbook, step 5, declare `Files` for every task and keep them disjoint. Shared files (`go.mod`, `package.json`, lockfiles) belong to exactly one task. Check with `sh "$T4L/scripts/t4l-task.sh" plan-check`; fix the plan until it is clean.
2. **Gate.** For `sdd`, the specs are approved first (`approve`), as always.
3. **Launch the workflow-master** once, with this brief:
   ```
   DOC: .t4l/tasks/<feature>.md
   T4L_ROOT: <path>
   VERIFY: <the repo's verify command>
   BASE: <ref of the previous code, usually HEAD>
   ```
   While it runs, you do not edit project files and you do not launch implementers yourself.
4. **Read its report** `.t4l/reports/workflow_<feature>.md`: waves, final board, integration result, sizes, judge verdict, open items.
5. **Escalations.** It stops and reports instead of deciding when: the plan has overlaps, a task needs a file outside its `Files`, a conflict is semantic, or two judge rounds did not approve. Decide, amend the plan if needed (`add`, `reopen`, `log`), and launch it again.
6. **Close.** Once the judge approved and the tasks are `done`: `t4l-task.sh check`, `t4l-task.sh close`.
7. **Ship.** The integrated work is on the branch `t4l/<feature>/integration`, in the worktree `.t4l/worktrees/integration`. The workflow-master proposes slices when the total exceeds the budget. Follow the `ship` playbook for the commits and the PR; merging to `main` and pushing are the user's.

## Reply format

- Tasks run in parallel and in which waves.
- Integration result and the judge verdict, with the key evidence lines.
- Sizes and the proposed slices.
- Open items and anything that was not shipped.
