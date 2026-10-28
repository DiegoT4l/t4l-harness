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

## Scope

t4l runs shell hooks and scripts on the user's machine, so these are in scope:

- a hook or script that runs commands from a cloned repository without the user's consent (for example, bypassing the `T4L_TRUST_CONFIG` rule for a committed `.t4l/config`);
- shell injection through file paths, configuration values or hook input;
- `install.sh` or the version check doing anything beyond what they document;
- a workflow in `.github/workflows` that exposes `RELEASE_PLEASE_TOKEN` or runs untrusted code with write access.

Out of scope: what a command configured in your own `.t4l/config` does, and vulnerabilities in Claude Code itself, which go to [Anthropic](https://www.anthropic.com/responsible-disclosure-policy).
