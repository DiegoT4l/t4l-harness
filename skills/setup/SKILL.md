---
name: setup
description: Check this machine for the tools t4l uses (git, jq, timeout, and the optional claude, gremlins, ccc, markitdown, pi-worker, engram) and report which features are active, plus whether the current repository has the verification hooks on. Use when the user types /t4l:setup, just installed the plugin, or asks why a t4l feature is not working.
disable-model-invocation: true
---

# t4l setup

A read-only check. It installs nothing and writes nothing.

## Steps

1. Run the check from the current directory:

   ```bash
   sh "${CLAUDE_PLUGIN_ROOT}/scripts/t4l-setup.sh"
   ```

   If `CLAUDE_PLUGIN_ROOT` is empty, use `../../scripts/t4l-setup.sh` relative to this skill's directory.

2. Summarize the result for the user in a few lines:
   - A missing **required** tool (exit status 1) blocks t4l. Say so first.
   - A missing **recommended** tool degrades a feature; the output says how.
   - A missing **optional** tool only turns off the feature on its line. Do not push the user to install everything.

3. For each missing tool the user wants, show the install command from the output and run it only if the user asks you to.

4. If the verification hooks are off for this repository because there is no `.t4l/config`, offer `/t4l:init`. If they are off because the config is tracked by git, explain that a cloned repository must not run commands on this machine, and that `T4L_TRUST_CONFIG=1` allows it.
