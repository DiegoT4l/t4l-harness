# Playbook: feature (large lane)

For new or changed behavior that fails the resume test. The lead owns the design, the document and the verification; the `t4l:implementer` writes the code; the `t4l:judge` decides. In this lane the lead does not edit project files: a hook blocks it.

`T4L` below is the `T4L_ROOT` path announced at the top of the session context. `TASK="sh $T4L/scripts/t4l-task.sh"`.

## Steps

1. **Understand.** Explore within the evidence budget (`t4l-search.sh` for conceptual questions when ccc is enabled, the built-in `Explore` agent for more than ~5 lookups). If the user gave documents (requirements in docx, xlsx, pptx...), ingest them first with `t4l-ingest.sh`: the specs will quote them from `.t4l/inputs/`. Name the data shape first. Decide the mode: `sdd` when behavior must be invented or is public, otherwise `tdd`.
2. **Open the feature.**
   ```bash
   $TASK new <feature> --mode <sdd|tdd> --request "<the user's request, verbatim>"
   ```
   This creates `.t4l/tasks/<feature>.md` and `.t4l/state`. With `sdd`, the guard now blocks every write outside `.t4l/` until the specs are approved.
3. **Write the specs** in the document: `S1..Sn` quoting the user's exact strings, scenarios (Given/When/Then), `Existing behavior at risk` (read the code that will change and search for every entry point that reaches it, with `t4l-search.sh` when available; include text that looks like an option, empty input, new argument positions) and the assumptions to confirm. Mirror the document to Engram under `t4l/<feature>/tasks`.
4. **Gate (sdd).** Show the specs, list the assumptions and stop. After the user approves, run `$TASK approve`. It refuses specs that are still the template or lack `Existing behavior at risk`.
5. **Plan the tasks.** One task per coherent behavior, each about 400 changed lines or less, with its tests and docs:
   ```bash
   $TASK add T1 S1 --files 'cmd/**,internal/slug/**'
   $TASK add T2 S2 --deps T1 --files 'internal/web/**'
   ```
   Declare `Files` as globs; two tasks must not own the same file. Shared files (`go.mod`, `package.json`, lockfiles) belong to exactly one task.
6. **Build.** If two or more tasks have disjoint `Files` and no dependency chain, follow the `parallel` playbook instead of this step and the next. Otherwise, one task at a time. For each task in dependency order:
   - Launch the `t4l:implementer` with a brief like this (all fields are required):
     ```
     DOC: .t4l/tasks/<feature>.md
     TASK: T1
     T4L_ROOT: <path>
     COMMIT: <yes|no>   (yes only if the user authorized commits)
     VERIFY: <the repo's verify command>
     ```
   - Read its report (`.t4l/reports/impl_<feature>_<TASK>.md`), not the whole transcript. Check that the RED/GREEN blocks and the `Regression:` line are there. If not, send it back.
   - A task that depends on another can start as soon as that one is in `review`; you do not need a judge between them. If the judge later rejects the first task, reopen it and every task that depends on it.
7. **Review.** When every task is in `review`:
   - If the risk is high (auth, money, data loss, concurrency, public API) or the diff is above ~400 lines, launch the `t4l:reviewer` once per relevant lens, one lens per launch (`LENS`, `BASE`, `DOC`).
   - Launch the `t4l:judge` with `DOC`, `T4L_ROOT` and `BASE` (the ref of the previous code).
8. **Act on the verdict.**
   - `CHANGES_REQUESTED`: for each affected task run `$TASK reopen <ID> "<reason>"`, relaunch the implementer with the required changes, then the judge again. After two rounds without approval, stop and ask the user.
   - `APPROVED`: run `$TASK done <ID> [sha]` for each task, then `$TASK check` and `$TASK close`.
9. **Requirement changes.** Rewrite only the affected specs, reopen only their tasks, and log the reason with `$TASK log`.
10. **Close.** Offer the `ship` playbook.

## Reply format

- What was built and the specs it satisfies (`S1..Sn`).
- The judge verdict and the key evidence lines (RED, GREEN, `Regression:`), in code blocks.
- Decisions taken and open questions.
- What is not committed or not shipped.

Save the decisions and non-obvious findings to Engram.
