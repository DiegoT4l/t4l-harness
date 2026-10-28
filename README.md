# t4l-harness

A Claude Code plugin that adapts the engineering process to each task. ODD is the backbone: small work stays small. TDD and SDD are modes the router turns on when the task calls for them. Rules that a hook or a script can check are checked by one, not left as prose.

It takes ideas, not code, from three reference harnesses:

| Reference | What it contributes |
|---|---|
| [pstack](https://github.com/cursor/plugins/tree/main/harness/pstack) | Playbooks per task type, engineering principles, quality over volume, independent verification |
| [gentle-ai](https://github.com/Gentleman-Programming/gentle-ai) | Persistent memory (Engram), ODD, evidence, benchmarking |
| [harness-sdd (uncle-bob-harness)](https://github.com/betta-tech/harness-sdd/tree/uncle-bob-harness) | Spec → Gherkin → TDD → judge → mutation pipeline, human gate, state on disk |

None of them fits as is. This repository decides, piece by piece, what to adopt, adapt or drop. The analysis is in [`docs/references.md`](docs/references.md) and the design in [`docs/design.md`](docs/design.md). Both documents are in Spanish.

## How it works

- **Router (`/t4l`).** It first checks whether the request authorizes a change. Then it explores proportionately and puts the task in a lane: **read-only**, **small** (inline, no task document) or **large** (feature document, contract, gates). It also picks the mode: **ODD only**, **ODD + TDD** or **ODD + SDD**, and declares it in one line.
- **Playbooks.** `investigate`, `bug`, `feature`, `refactor`, `perf`, `ship` and `parallel`.
- **Agents.** All of them start with fresh context:
  - `implementer`: one task, test-first.
  - `judge`: read-only; approves or requests changes.
  - `reviewer`: one lens per launch.
  - `workflow-master`: Kanban board, parallel implementers in isolated worktrees.
- **Enforcement.**
  - `guard` blocks writes before spec approval and outside a task's scope.
  - Opt-in verification hooks: a quick check after each edit and the full verify before a turn ends.
  - A branch guard and a slice-size warning.
- **Measurement.** Journeys replay real headless sessions on a throwaway fixture and judge them with deterministic checkpoints. Use them to compare harness versions. A new playbook has to earn its place with a journey that fails without it.

## Layout

```
install.sh       one-line installer (curl | sh)
.github/         CI and release workflows
.claude-plugin/  plugin manifest and the marketplace that lists it
rules/           kernel injected into every session (t4l.md)
skills/          t4l (router + playbooks), setup, init, correct
agents/          implementer, judge, reviewer, workflow-master
hooks/           hooks.json + POSIX sh hooks (guard, verification, branches, size, kernel)
scripts/         t4l-setup, t4l-version, t4l-init, t4l-task, t4l-regress, t4l-size, t4l-integrate, t4l-search,
                 t4l-ingest, t4l-checkpoints, t4l-journey, t4l-mutate, t4l-package
journeys/        reproducible sessions that measure the harness, with the slug fixture and shared states
tests/           hooks, regress, task, size, integrate, integrations, journey, mutate, package, setup, install, version
docs/            references, design, manual test scenarios (Spanish)
```

## Install

From a terminal, with Claude Code already installed:

```bash
curl -fsSL https://raw.githubusercontent.com/DiegoT4l/t4l-harness/main/install.sh | sh
```

It runs the `claude plugin` commands below: it adds this repository as a marketplace and installs or updates `t4l`. It is safe to run again. Pass `sh -s -- --scope project` to install it for the current project only. Read [`install.sh`](install.sh) before piping it into a shell.

It also turns on Claude Code's auto-update for this marketplace, by setting `autoUpdate` on its entry in your settings file (this needs `jq`; pass `--no-auto-update` to skip it). With it on, Claude Code checks for a new release in the background during a session, installs it, and loads it on `/reload-plugins` or the next launch.

Or from inside Claude Code, since this repository is also a plugin marketplace:

```
/plugin install t4l --marketplace DiegoT4l/t4l-harness
```

On Claude Code older than 2.1.275, add the marketplace first:

```
/plugin marketplace add DiegoT4l/t4l-harness
/plugin install t4l@t4l-harness
```

To turn auto-update on without the script: `/plugin`, **Marketplaces**, `t4l-harness`, **Enable auto-update**. Without it, `claude plugin update t4l@t4l-harness` pulls the latest version; restart Claude Code to apply it.

**Version check.** Once a day, in the background, t4l fetches the version on `main`. When it is newer than the one running, the session starts with a one-line notice. `sh scripts/t4l-version.sh` checks right away, and `/t4l:setup` includes it. `T4L_UPDATE_CHECK=off` turns the check off; a checkout loaded with `--plugin-dir` never gets the notice.

Other ways to load it, without installing:

- From a checkout: `claude --plugin-dir ~/t4l-harness`.
- From a release: download `t4l-<version>.zip` from the GitHub Releases page and run `claude --plugin-dir t4l-<version>.zip`.

The `SessionStart` hook injects the kernel, so nothing needs to be copied into `~/.claude`.

## Use it

- `/t4l:setup` checks the machine: `git` is required, `jq` and `timeout` are recommended, and every optional tool turns on one feature. It also says whether the current repository has the verification hooks on. It only reads.
- `/t4l:init` enables the verification hooks in a repository by writing `.t4l/config`. It detects Go and TypeScript.
- `/t4l` routes a request. The router also triggers on its own when a request asks for a change.
- `/t4l:correct` turns a repeated correction into an enforced rule.

Per-repository state lives in `.t4l/`, which is git-ignored.

## Status

| Version | What it added |
|---|---|
| v0.1 | Kernel, router, method selector (ODD / TDD / SDD), `investigate` and `bug` playbooks |
| v0.2 | Opt-in verification hooks (`/t4l:init`), `/t4l:correct`, rule ↔ enforcer table |
| v0.3 | Large lane: feature document (`t4l-task.sh`), `guard`, `implementer`, `judge` and `reviewer` agents, `feature`, `refactor` and `ship` playbooks, regression check (`t4l-regress.sh` with `{edge}`) |
| v0.4 | `workflow-master`: Kanban board with a WIP limit, parallel mode in isolated worktrees, per-task scope enforced by `guard`, slice size (`t4l-size.sh`), integration on a separate branch (`t4l-integrate.sh`) |
| v0.4.1 | Optional semantic code search (cocoindex-code, `t4l-search.sh`) and document ingestion (markitdown, `t4l-ingest.sh`) |
| v0.5 | Measurement: generic final-state checkpoints (`t4l-checkpoints.sh`) and headless journeys (`t4l-journey.sh`) |
| v0.5.1 | `pickup` journeys. No playbook: both pass without one |
| v0.5.2 | Optional mutation testing of changed code (`t4l-mutate.sh`, Go with gremlins); the `judge` treats surviving mutants as missing tests |
| v0.5.3 | `perf` playbook (journey pass rate 0/3 without it, 2/3 with it). `babysit` journey, no playbook: it passes without one |
| v0.5.4 | CI pipelines and release-please releases with the plugin zip attached |
| v1.0 | Plugin: marketplace in this repository, `/t4l:setup`, install documentation |

## Test and measure

Script tests (no tokens spent):

```bash
for t in hooks regress task size integrate integrations journey mutate package setup install version; do sh tests/$t.sh; done
```

Journeys run real sessions and spend tokens: about 6 USD and 10 minutes for all twelve with the default model. Each one runs in a throwaway copy of `journeys/fixtures/slug`, with Engram disabled so that measurement runs do not write to your memory.

```bash
sh scripts/t4l-journey.sh --list
sh scripts/t4l-journey.sh --all                        # results in .t4l/journeys/<date>-<rev>
sh scripts/t4l-journey.sh --repeat 3 perf              # pass rate over several runs
sh scripts/t4l-journey.sh --plugin-dir ../old-version --out .t4l/journeys/A perf
sh scripts/t4l-journey.sh --compare .t4l/journeys/A .t4l/journeys/B
```

The manual scenarios and what to look for are in [`docs/testing.md`](docs/testing.md).

## Development workflow

- **Branches.** `main <- dev <- feature branch`. `main` is the default branch and holds released code, so the marketplace and a fresh clone get the latest release. `dev` integrates the work: open feature branches from `dev` and send them back to `dev` by PR (pick `dev` as the base, since GitHub proposes `main`). `main` only receives PRs from `dev`, and every merge into it is a candidate release.
- **CI** (`.github/workflows/ci.yml`) runs on every PR and push to `dev` and `main`:
  - `lint`: shellcheck 0.11.0 and actionlint, both pinned and checksum-verified, plus the manifest checks (`plugin.json`, `marketplace.json`, hooks);
  - `test`: one job per shell suite, with Go and gremlins installed;
  - `package`: builds the plugin zip and checks what it contains.
- **Releases** (`.github/workflows/release.yml`) use [release-please](https://github.com/googleapis/release-please).
  - On each push to `main` it keeps a release PR up to date. The PR bumps `.claude-plugin/plugin.json` and `.release-please-manifest.json`, and writes `CHANGELOG.md` from the Conventional Commits.
  - Merging that PR tags `vX.Y.Z` and creates the GitHub Release, with `t4l-<version>.zip` attached.
  - The release commit exists only on `main`, so the same workflow opens a `main -> dev` PR with auto-merge on. It merges itself once CI is green, and `dev` stays the most up-to-date branch. Merge `dev -> main` PRs with a merge commit, not squash or rebase, so that `main` stays an ancestor of `dev`.
- **Protection.** A ruleset on `dev` and `main` blocks deletion and force pushes, and requires a PR with every CI check green. release-please opens its PR with the `RELEASE_PLEASE_TOKEN` Actions secret, so CI runs on it too.
- **Versioning.** Semantic versioning from the Conventional Commits: `fix` bumps the patch, `feat` the minor, and a breaking change (`!` or a `BREAKING CHANGE:` footer) the major. The marketplace entry carries no version, so `plugin.json` is the only place it lives. To force a specific version, add a `Release-As: X.Y.Z` footer to a commit.
- **Releasable commits.** `ci`, `build`, `chore`, `docs`, `test` and `refactor` commits alone do not open a release PR.

## Optional integrations

t4l works without them. The `SessionStart` hook announces the ones that are installed, and `/t4l:setup` lists them all with what each one enables.

```bash
uv tool install 'cocoindex-code[full]'                          # semantic code search (ccc)
uv tool install 'markitdown[all]'                               # documents to Markdown
go install github.com/go-gremlins/gremlins/cmd/gremlins@v0.6.0  # mutation testing for Go
```

To enable search in a repository, run `sh scripts/t4l-search.sh --init`; the index stays local. To enable mutation testing, set `mutation=gremlins` in `.t4l/config`.

## Environment constraints

- No AI attribution in commits, PRs or code. The `block-ai-attribution` hook in `~/.claude` enforces it.
- No Homebrew: install with pacman or paru, or use upstream binaries.
- It must coexist with `engram` and `pi-workers` without duplicating them.

## License

[Apache License 2.0](LICENSE).
