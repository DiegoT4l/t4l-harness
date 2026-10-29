# Security policy

## Reporting a vulnerability

Report vulnerabilities privately through [GitHub's private vulnerability reporting](https://github.com/DiegoT4l/t4l-harness/security/advisories/new). Do not open a public issue, pull request or discussion for them.

Include what you can:

- the t4l version (`claude plugin list`) and the Claude Code version (`claude --version`);
- the component: a hook, a script, `install.sh`, the release workflow;
- the steps to reproduce and what an attacker gains.

You will get an answer in the advisory. Once a fix is released, the advisory is published with credit to you, unless you prefer otherwise.

## Supported versions

Only the latest release gets security fixes. Installs from `install.sh` or with auto-update on receive it without doing anything.

## What the hooks protect against

t4l's hooks keep an agent on the process: no code before the specs are approved, the lead delegates instead of editing, the judge and the reviewer only write their reports, each parallel implementer stays inside its task's files, no commits on protected branches. They catch an agent that drifts or takes a shortcut. They are not a sandbox and do not stop a determined attacker.

- `guard` blocks Edit and Write before they happen. `bash-guard` compares the files git sees before and after each Bash command and reports a write that `guard` would have refused. It detects after the fact, does not undo, and does not see files ignored by git (other than `.t4l/`) or writes from a command left running in the background.
- `branch-guard` reads the command text. It is a first barrier, not a replacement for branch protection on the server.
- `T4L_GUARD=off`, `T4L_HOOKS=off` and `T4L_ALLOW_PROTECTED=1` turn controls off. They are read from the environment Claude Code started with, so a command the agent runs cannot set them.

For real isolation, use Claude Code's sandbox and `deny` permission rules, branch protection or rulesets on the Git server, and a throwaway clone without secrets for untrusted work. A way to defeat a hook is a bug worth reporting as an issue; it is a vulnerability only when it also falls under the scope below.

## Scope

t4l runs shell hooks and scripts on the user's machine, so these are in scope:

- a hook or script that runs commands from a cloned repository without the user's consent (for example, bypassing the `T4L_TRUST_CONFIG` rule for a committed `.t4l/config`);
- shell injection through file paths, configuration values or hook input;
- `install.sh` or the version check doing anything beyond what they document;
- a workflow in `.github/workflows` that exposes `RELEASE_PLEASE_TOKEN` or runs untrusted code with write access.

Out of scope: what a command configured in your own `.t4l/config` does, and vulnerabilities in Claude Code itself, which go to [Anthropic](https://www.anthropic.com/responsible-disclosure-policy).
