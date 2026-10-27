---
name: init
description: Enable t4l verification hooks in the current repository by generating .t4l/config from the detected stack (Go, TypeScript/JavaScript). Use when the user types /t4l:init or asks to turn on the quick check after edits and the full verification before finishing a turn.
disable-model-invocation: true
---

# t4l init

The hooks are opt-in per repository: they do nothing until `.t4l/config` exists.

## Steps

1. Run the generator from the repository root:

   ```bash
   sh "${CLAUDE_PLUGIN_ROOT}/scripts/t4l-init.sh"
   ```

   If `CLAUDE_PLUGIN_ROOT` is empty, use `../../scripts/t4l-init.sh` relative to this skill's directory. It refuses to overwrite an existing config; pass `--force` only if the user asked to regenerate it.

2. Show the user the generated config and check it against reality:
   - Run the `verify` command once. If it fails for reasons unrelated to the task (missing tool, broken baseline), tell the user and do not "fix" the config to hide it.
   - If the stack has a faster check than the default, or none was detected, propose the exact `quick` and `verify` lines and ask before writing them.

3. If the generator reports that ccc is installed but not enabled, offer to enable semantic code search with the command it prints (it indexes locally and keeps the tracked `.gitignore` untouched). Run it only if the user agrees.

4. Tell the user how it behaves:
   - `quick` runs after every Edit/Write of a file whose extension is in `quick_ext`. Silent on success; on failure the output is returned to the agent.
   - `verify` runs once before the agent ends a turn, only if the working tree has changes. If it fails, the agent gets one chance to fix it.
   - `.t4l/` is added to `.gitignore`. If the config is committed anyway, its commands will not run unless `T4L_TRUST_CONFIG=1`, because a cloned repo must not be able to run commands on the user's machine.
   - Turn everything off with `disable=1` in the config or `T4L_HOOKS=off` in the environment.

Do not commit the config.
