# Análisis de los tres harnesses de referencia

Lectura realizada: pstack (README, adaptador Claude Code, `poteto-mode`, playbooks bug-fix/feature, skills `correct` e `interrogate`, lista de 58 skills), gentle-ai (README, sección ODD de `usage.md`, orquestador de Claude, agentes de review, protocolo Engram, skill registry) y harness-sdd rama `uncle-bob-harness` (README, CLAUDE.md, workflow, agentes, settings, CHECKPOINTS, init.sh, docs de TDD y mutación).
No se auditó el código de los scripts (watch-pr, orch, mutate.py) ni el binario Go de gentle-ai.

Los tres resuelven **problemas distintos**, por eso ninguno convence solo:

| | pstack | gentle-ai | uncle-bob |
|---|---|---|---|
| Qué es en esencia | Biblioteca de **criterio**: principios + playbooks | **Runtime** de enrutado: clasifica, rastrea, delega, revisa | **Pipeline** con puertas: contrato → TDD → juicio → mutación |
| Pregunta que responde | "¿Cómo pienso esta tarea?" | "¿Cuánto proceso merece esta tarea y cómo no pierdo contexto?" | "¿Cómo demuestro que el código es correcto?" |
| Punto de entrada | `/poteto-mode` (manual) | Automático en cada pedido (ODD) | Rol fijo en `CLAUDE.md` |
| Estado | Chat + TSV opcional | Documento por feature + Engram | `feature_list.json` + `progress/*.md` |
| Verificación | Superficie real, repro antes del fix | Checks proporcionales + review por riesgo | Hooks + juez + mutación |

---

## 1. pstack

### Qué tiene de valioso
- **Principios citables** (28 skills `principle-*`). Los que más rinden:
  `prove-it-works` (verificar contra el artefacto real), `fix-root-causes`, `laziness-protocol` y `subtract-before-you-add` (sesgo a borrar), `sequence-verifiable-units`, `guard-the-context-window`, `test-behavior-not-implementation`, `never-block-on-the-human` (no preguntar en trabajo reversible), `attack-the-premise` (cuando dos fixes con la misma premisa fallan, probar la premisa).
- **Playbooks por tipo de tarea** con "Reply" definido. Bug-fix: reproducir tú mismo, búsqueda binaria de la causa con evidencia de runtime, el repro que falla va en un commit antes del fix. Feature: nombrar la forma de los datos primero, diseño en paralelo, "throughput checkpoint" de 4 puntos.
- **`correct`**: convierte correcciones repetidas en estructura, en este orden: arquitectura → tipos → lint con mensaje que nombra el arreglo → test → docs al final. Mantiene una tabla regla ↔ qué la hace cumplir. Es la idea más reutilizable de todo pstack: "nada falla si el agente ignora un doc".
- **`show-me-your-work`**: bitácora TSV de decisiones para trabajo desatendido.
- **`how` / `why` / `blast-radius`**: entender antes de tocar; qué se puede romper fuera del diff, probado con código real.

### Qué no sirve para nosotros
- Acoplado a Cursor: adaptador obligatorio, `Skill` rechaza sus skills, hay que leer `SKILL.md` a mano.
- Valor multimodelo (`interrogate`, `arena`, panel Opus/grok) que con un solo proveedor se pierde.
- Superficie enorme (58 skills, 23 playbooks, scripts Bun/TS, `make-bot-ui`, `ketchup-video`, verificación formal).
- Los skills clave son `disable-model-invocation`: dependen de que escribas `/poteto-mode`.
- Tono y estilo personales del autor (`unslop`, `bro`, prosa en minúsculas).

---

## 2. gentle-ai

### Qué tiene de valioso
- **ODD**: la clasificación por **prueba de reanudación** ("¿se puede retomar solo con el pedido y `git diff`?"), nunca por número de archivos. Lo pequeño corre inline, sin subagentes ni documento. Es la regla más fina de los tres.
- **Autorizar antes de tocar**: pregunta, review y propuesta son solo lectura; solo un pedido que autoriza un cambio escribe.
- **Documento único por feature** (`odd/tasks/<feature>.md`): cabecera, `## Specs` con `S#` que citan tus textos **literales**, `## Tasks` (ID, `S#`, ruta, commit), `## Log` con `L1` = tu pedido original verbatim. Los workers reciben **referencia al documento**, no un resumen (cero teléfono descompuesto). Un cambio de requisito reabre solo la tarea afectada.
- **Espejo en Engram** del documento + lectura de vuelta (las dos escrituras no son atómicas).
- **Reglas de delegación con números**: presupuesto de evidencia inline (≤3 llamadas, ~10k tokens), más de ~5 búsquedas secuenciales → un explorador de solo lectura que devuelve ≤2k tokens con `path:línea`; escritor delegado solo para unidades paralelas disjuntas o por contexto.
- **Test-first por defecto** cuando hay test determinista ejecutable, y regresión explícita: por cada comando que comparte el código cambiado, ejecutar contra HEAD anterior y contra el cambio y comparar stdout, stderr y exit code.
- **Entrega en rebanadas** de ~400 líneas, Conventional Commits, tests y docs junto al comportamiento; un riesgo alto va en su propio commit.
- **Review con lentes** (Risk, Readability, Reliability, Resilience): solo lectura, **precision gate** ("si hay duda, no reportar: un falso positivo cuesta un ciclo de fix"), un barrido por lente, ledger con `id/severity/evidence`, y un `refuter` aparte para hallazgos graves solo inferenciales.
- **Bench** de "journeys" para medir regresiones del propio harness.

### Qué no sirve para nosotros
- Es un instalador/configurador para 17 agentes con binario Go, telemetría, firmas de release, Windows/macOS. Nada de eso aplica a un solo agente.
- Orquestador de ~19 KB de prompt, con ceremonias (RDD consent, handoff de defectos del proveedor, preguntas bloqueantes sin pérdida) que cuestan contexto en cada sesión.
- Ligado a su CLI (`gentle-ai review assess`, `skill-registry refresh`).

---

## 3. harness-sdd, rama uncle-bob-harness

### Qué tiene de valioso
- **Una sola puerta humana, sobre el contrato** (Gherkin) y antes de producir código. Aprobar tarde es caro; aprobar el contrato es barato.
- **Escenarios `@s1..@sn`** como trazabilidad: cada escenario ↔ un test; el juez rechaza si falta cobertura.
- **El lead orquesta y no implementa** (sin Edit/Write sobre `src/` ni `tests/`).
- **Hooks que verifican por el harness** (PostToolUse: tests tras editar; Stop: `init.sh` completo), así que el agente no puede saltárselos.
- **Informes a disco** (`progress/tdd_*`, `judge_*`, `mutation_*`) en vez de en el chat.
- **Juez de solo lectura**: aprueba o poda, no edita. Quien escribe no revisa.
- **Mutación** como medida real de si los tests muerden, con mutantes sobrevivientes documentados.
- **`CHECKPOINTS.md`**: se evalúa el estado final, no el camino.
- **`feature_list.json`**: máquina de estados explícita (`pending → spec_ready → in_progress → done`), una feature a la vez.

### Qué no sirve para nosotros
- Pipeline **fijo y pesado**: spec + Gherkin + TDD + juicio + mutación aunque el cambio sea de una línea.
- Python/unittest y `mutate.py` textual casero (mutaciones por regex).
- Andamiaje por repo (`init.sh`, `feature_list.json`, `docs/*`) que hay que replicar en cada proyecto.
- Un único flujo: no distingue bug, refactor, investigación o perf.
- Rol obligatorio vía `CLAUDE.md`: no se puede usar para trabajo ajeno al pipeline sin excepciones escritas a mano.

---

## Qué aporta cada uno a la fusión (resumen)

| Capa | Fuente principal |
|---|---|
| Cuánto proceso aplicar (clasificación, autorización) | gentle-ai (ODD) |
| Cómo pensar cada tipo de tarea (playbooks, principios) | pstack |
| Cómo se prueba que está bien (contrato, TDD, juez, mutación, hooks) | uncle-bob |
| Cómo no perder contexto (documento único, Engram, handoff por referencia) | gentle-ai |
| Cómo se vuelve estructura lo que se repite (`correct`) | pstack |
| Cómo se revisa (lentes, precision gate, refuter) | gentle-ai + juez de uncle-bob |
| Cómo se mide el harness (checkpoints, journeys) | uncle-bob + gentle-ai |
