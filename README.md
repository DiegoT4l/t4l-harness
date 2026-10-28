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
.github/         CI and release workflows
.claude-plugin/  plugin manifest
rules/           kernel injected into every session (t4l.md)
skills/          t4l (router + playbooks), init, correct
agents/          implementer, judge, reviewer, workflow-master
hooks/           hooks.json + POSIX sh hooks (guard, verification, branches, size, kernel)
scripts/         t4l-init, t4l-task, t4l-regress, t4l-size, t4l-integrate, t4l-search,
                 t4l-ingest, t4l-checkpoints, t4l-journey, t4l-mutate, t4l-package
journeys/        reproducible sessions that measure the harness, with the slug fixture and shared states
tests/           hooks, regress, task, size, integrate, integrations, journey, mutate, package
docs/            references, design, manual test scenarios (Spanish)
```

## Use it

From a checkout:

```bash
claude --plugin-dir ~/t4l-harness
```

Or from a release: download `t4l-<version>.zip` from the GitHub Releases page and run `claude --plugin-dir t4l-<version>.zip`.

The `SessionStart` hook injects the kernel, so nothing needs to be copied into `~/.claude`. In each repository:

- `/t4l:init` enables the verification hooks by writing `.t4l/config`. It detects Go and TypeScript.
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

Next: v1.0, packaging (`t4l:setup`, a marketplace in this repository, documentation).

## Test and measure

Script tests (no tokens spent):

```bash
for t in hooks regress task size integrate integrations journey mutate package; do sh tests/$t.sh; done
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

- **Branches.** `dev` is the default branch and integrates the work. Open feature branches from `dev` and send them back by PR. `main` only receives PRs from `dev`, and every merge into it is a candidate release.
- **CI** (`.github/workflows/ci.yml`) runs on every PR and push to `dev` and `main`:
  - `lint`: shellcheck 0.11.0 and actionlint, both pinned and checksum-verified, plus the manifest checks;
  - `test`: one job per shell suite, with Go and gremlins installed;
  - `package`: builds the plugin zip and checks what it contains.
- **Releases** (`.github/workflows/release.yml`) use [release-please](https://github.com/googleapis/release-please).
  - On each push to `main` it keeps a release PR up to date. The PR bumps `.claude-plugin/plugin.json`, `version.txt` and `.release-please-manifest.json`, and writes `CHANGELOG.md` from the Conventional Commits.
  - Merging that PR tags `vX.Y.Z` and creates the GitHub Release, with `t4l-<version>.zip` attached.
- **Versioning before 1.0.** `feat` and `fix` bump the patch version, and a breaking change bumps the minor. To release a milestone as a specific version, add a `Release-As: 0.6.0` footer to a commit.
- **Releasable commits.** `ci`, `build`, `chore`, `docs`, `test` and `refactor` commits alone do not open a release PR.

## Optional integrations

t4l works without them. The `SessionStart` hook announces the ones that are installed.

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
