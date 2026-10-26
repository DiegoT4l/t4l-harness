# t4l-harness

Harness propio para Claude Code, construido a partir de lo mejor de tres harnesses de referencia:

| Referencia | Qué nos interesa |
|---|---|
| [pstack](https://github.com/cursor/plugins/tree/main/harness/pstack) | Playbooks por tipo de tarea, principios de ingeniería, calidad sobre volumen, verificación independiente |
| [gentle-ai](https://github.com/Gentleman-Programming/gentle-ai) | Memoria persistente (Engram), ODD (trabajo pequeño se mantiene pequeño), evidencia, bench |
| [harness-sdd (uncle-bob-harness)](https://github.com/betta-tech/harness-sdd/tree/uncle-bob-harness) | Pipeline spec → Gherkin → TDD → judge → mutación, puerta humana, estado en disco |

Ninguno convence por completo. Este repo decide, pieza por pieza, qué se adopta, qué se adapta y qué se descarta. El análisis está en [`docs/references.md`](docs/references.md) y las decisiones abiertas en [`docs/design.md`](docs/design.md).

## Estructura

```
.claude-plugin/  manifest del plugin
rules/           kernel que se inyecta en cada sesión (t4l.md)
skills/          t4l (router + playbooks), init, correct
agents/          implementer, judge, reviewer
hooks/           hooks.json + scripts POSIX sh (guard, verificación, kernel)
scripts/         t4l-init, t4l-task, t4l-regress
tests/           hooks.sh, regress.sh, task.sh
docs/            referencias, diseño, cómo probar
```

## Estado

**v0.3.** Kernel, router `t4l` con selector de método (ODD / TDD / SDD), playbooks `investigate`, `bug`, `feature`, `refactor` y `ship`, hooks de verificación opt-in (`/t4l:init`), `/t4l:correct`, chequeo de regresión (`t4l-regress.sh` con `{edge}`) y carril grande completo: documento de feature gestionado por `t4l-task.sh`, hook `guard` (puerta SDD y lead que no implementa) y agentes `implementer`, `judge` y `reviewer`. El `workflow-master` (tablero Kanban, worktrees, paralelismo e integración) llega en la v0.4; ver `docs/design.md`.

## Probar

```bash
cd ~/t4l-sandbox && claude --plugin-dir ~/t4l-harness
```

Escenarios y qué observar en [`docs/testing.md`](docs/testing.md). Tests de los scripts: `sh tests/hooks.sh && sh tests/regress.sh && sh tests/task.sh`.

## Restricciones heredadas del entorno

- Sin rastro de IA en commits, PRs ni código (hook `block-ai-attribution` ya activo en `~/.claude`).
- Sin Homebrew; instalación vía pacman/paru o binarios upstream.
- Debe convivir con `engram` y `pi-workers`, sin duplicarlos.
