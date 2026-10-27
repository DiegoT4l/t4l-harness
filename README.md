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
agents/          implementer, judge, reviewer, workflow-master
hooks/           hooks.json + scripts POSIX sh (guard, verificación, ramas, tamaño, kernel)
scripts/         t4l-init, t4l-task, t4l-regress, t4l-size, t4l-integrate
tests/           hooks, regress, task, size, integrate
docs/            referencias, diseño, cómo probar
```

## Estado

**v0.4.** Kernel, router `t4l` con selector de método (ODD / TDD / SDD), playbooks `investigate`, `bug`, `feature`, `refactor`, `ship` y `parallel`, hooks de verificación opt-in (`/t4l:init`), `/t4l:correct`, chequeo de regresión (`t4l-regress.sh` con `{edge}`), carril grande completo (documento de feature con `t4l-task.sh`, `guard`, agentes `implementer`, `judge` y `reviewer`) y el **`workflow-master`**: tablero Kanban con límite WIP, modo paralelo en worktrees aislados, alcance por tarea hecho cumplir por el `guard`, medición de tamaño por rebanada (`t4l-size.sh`) e integración en una rama aparte (`t4l-integrate.sh`). Ver `docs/design.md`.

## Probar

```bash
cd ~/t4l-sandbox && claude --plugin-dir ~/t4l-harness
```

Escenarios y qué observar en [`docs/testing.md`](docs/testing.md). Tests de los scripts: `for t in hooks regress task size integrate; do sh tests/$t.sh; done`.

## Restricciones heredadas del entorno

- Sin rastro de IA en commits, PRs ni código (hook `block-ai-attribution` ya activo en `~/.claude`).
- Sin Homebrew; instalación vía pacman/paru o binarios upstream.
- Debe convivir con `engram` y `pi-workers`, sin duplicarlos.
