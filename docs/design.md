# Diseño de t4l-harness (propuesta v0)

Fusión de pstack (criterio), gentle-ai (enrutado y contexto) y uncle-bob (puertas y verificación), para **un solo agente: Claude Code**, con un solo proveedor de modelos. Análisis de origen en [`references.md`](references.md).

## 1. Principios de diseño

1. **El proceso es proporcional.** Lo pequeño se queda pequeño (ODD). Solo el trabajo grande recibe contrato, documento y puertas.
2. **Lo que puede verificar un hook, lo verifica un hook.** Un doc que el agente puede ignorar no es una garantía (`correct`).
3. **ODD es la columna vertebral; TDD y SDD son modos que se activan según la tarea.** ODD decide cuánto proceso y cuánto rastro; TDD decide cómo se conduce el código; SDD decide si hace falta un contrato aprobado antes de escribir. Nada se aplica por defecto "porque sí".
4. **Quien escribe no revisa.** El revisor es de solo lectura y arranca con contexto fresco.
5. **El contexto vive en disco y en Engram, no en el chat.** Los subagentes reciben una referencia, nunca un resumen.
6. **Evidencia observada, no autoinforme.** Un check solo se marca con salida real (`prove-it-works`).
7. **Sesgo a borrar.** Menos código, menos capas (`laziness-protocol`, `subtract-before-you-add`).
8. **El kernel es chico.** Si una regla no cambia el comportamiento en la mayoría de las sesiones, no entra al kernel: va a un skill que se carga bajo demanda.

## 2. Arquitectura en cinco capas

```
┌──────────────────────────────────────────────────────────────┐
│ 5. MEDICIÓN     checkpoints + journeys (¿mejora el harness?)  │
├──────────────────────────────────────────────────────────────┤
│ 4. ENFORCEMENT  hooks + scripts + tabla regla↔enforcer        │
├──────────────────────────────────────────────────────────────┤
│ 3. AGENTES      implementer · judge · reviewer (+ Explore)   │
├──────────────────────────────────────────────────────────────┤
│ 2. PLAYBOOKS    investigate · bug · feature · refactor ·      │
│                 perf · ship · babysit · pickup                │
├──────────────────────────────────────────────────────────────┤
│ 1. ROUTER       Authorize → Explore → Classify (carriles)     │
├──────────────────────────────────────────────────────────────┤
│ 0. KERNEL       rules/t4l.md (siempre cargado, ≤150 líneas)   │
└──────────────────────────────────────────────────────────────┘
        Estado: Engram (entre sesiones) + .t4l/ (por repo)
```

### Capa 0 — Kernel (`rules/t4l.md`)
Se instala en `~/.claude/rules/` (se carga en cada sesión). Contiene solo:
- Los 8 principios de arriba, en versión de una línea.
- Regla de **autorización**: pregunta/explicación/review/propuesta = solo lectura.
- **Prueba de reanudación** para clasificar.
- **Reglas de delegación** con números (de gentle-ai): evidencia inline ≤3 llamadas / ~10k tokens; >5 búsquedas secuenciales → un explorador; escritor delegado solo por unidades paralelas disjuntas o por contexto.
- **Invariantes del entorno**: sin atribución de IA, sin Homebrew.
- **Idioma**: todo el contenido del harness (reglas, skills, agentes, prompts de subagentes) está en inglés. La respuesta al usuario va en el idioma de su último mensaje; si es español, español neutro (sin voseo ni regionalismos). Código, commits y PRs siguen el idioma del repo.
- Puntero a los skills `/t4l` y a la tabla regla↔enforcer.

No duplica el protocolo de Engram: el plugin `engram` ya inyecta el suyo.

### Capa 1 — Router (skill `t4l`, invocable por el modelo y por `/t4l`)

```
Pedido
  │
  ▼
¿Autoriza un cambio? ──no──► CARRIL LECTURA   (explicar, investigar, revisar, proponer)
  │ sí
  ▼
Explorar (proporcional)
  │
  ▼
¿Se puede retomar con pedido + git diff, riesgo contenido?
  ├─ sí ──► CARRIL PEQUEÑO   (inline, sin documento, check proporcional)
  └─ no ──► CARRIL GRANDE    (documento de feature + contrato + puertas)
```

- **Nunca** se decide por cantidad de archivos ni por tener una lista de tareas.

#### Selector de método: ODD + TDD / SDD según la tarea

ODD siempre está activo (es el que clasifica y rastrea). Sobre él, el router elige el **modo de conducción** de la tarea:

| Modo | Qué significa | Se elige cuando | Costo |
|---|---|---|---|
| **ODD solo** | Entender, cambiar, verificar con checks proporcionales. Sin test-first obligatorio ni contrato. | Cambio pequeño y entendido; config, docs, scripts; exploración; no hay test ejecutable razonable | Mínimo |
| **ODD + TDD** | Test-first: ROJO observado → VERDE → REFACTOR, un test a la vez. | Hay comportamiento observable y un test determinista ejecutable: bugs (el repro que falla va primero), lógica nueva acotada, refactors (tests de caracterización antes) | Bajo-medio |
| **ODD + SDD** | Contrato antes de código: specs `S#` con escenarios Given/When/Then, **aprobados por el usuario**, y luego TDD por escenario. | El comportamiento es ambiguo, tiene varios consumidores o es API pública; decisiones de producto reales; cambios que cruzan módulos o servicios; trabajo grande que otra persona o sesión retomará | Alto |

Reglas del selector:
1. **Se empieza por el modo más barato que alcance** y se sube solo si una señal lo exige: spec ambigua, dos intentos fallidos con la misma premisa, riesgo alto, necesidad de aprobación.
2. **SDD implica TDD**; TDD no implica SDD; ODD siempre está debajo.
3. **El tamaño no decide el modo.** Una tarea pequeña de API pública puede pedir SDD; una grande y mecánica (renombre masivo) puede ir con ODD solo más un check de regresión.
4. **El modo se declara en una línea** al clasificar ("ODD + TDD: bug con repro determinista") y queda en el documento de feature si existe. Se puede forzar: "usá SDD", "sin TDD".
5. **Mutación y reviewers son ortogonales al modo**: se activan por riesgo y por configuración del repo.
6. **Inventar comportamiento es la señal de SDD.** Si hay que decidir flags, valores por defecto, contrato de errores o casos límite que el usuario no especificó, no se asume en silencio: se escalan a SDD aunque el cambio sea pequeño.
7. **SDD ligero:** en el carril pequeño las specs van en la respuesta (`S#` con escenarios y la lista de supuestos a confirmar), sin documento ni espejo en Engram. Tras la aprobación se hace TDD por escenario, y si la tarea crece se promueve al carril grande.
8. **Chequeo de regresión** (de gentle-ai): antes de cerrar un cambio sobre código compartido se ejecutan los puntos de entrada existentes contra el código anterior y el nuevo, y se comparan stdout, stderr y exit code. Una diferencia no pedida es una regresión: se corrige y se fija con un test. Una regla en prosa no bastó (v0.2.2: el modelo lo omitió y dejó pasar una regresión real), así que lo hace un script (`scripts/t4l-regress.sh`), forma parte de los procedimientos de modo y el cierre exige una línea `Regression:`.
9. **`Existing behavior at risk`** en cada spec: obliga a pensar qué funciona hoy y podría cambiar antes de escribir código, y alimenta la lista del chequeo de regresión.
10. **Evidencia en bloque de código:** nombres de los tests que fallan, línea final de éxito y salida del comando real; "pegar literal" no se cumplía y un resumen en prosa no es evidencia.

Guía por tipo de tarea (valores por defecto, el router puede subir o bajar):

| Tipo de tarea | Modo por defecto |
|---|---|
| Explicar / investigar / revisar | Carril lectura, sin modo |
| Bug con repro determinista | ODD + TDD |
| Bug sin repro todavía | ODD solo hasta reproducir; luego TDD |
| Feature pequeña con comportamiento claro | ODD + TDD |
| Feature nueva con decisiones de producto o API pública | ODD + SDD |
| Refactor | ODD + TDD (caracterización) y comparación contra HEAD anterior |
| Perf | ODD solo + `explain-the-number` |
| Config, docs, scripts, migraciones mecánicas | ODD solo (mecánico masivo → `pi-workers`) |
- Si el pedido es ambiguo en una decisión **de producto**, una sola pregunta. Si la duda se resuelve ejecutando algo (comportamiento, timing, salida), no se pregunta: se prueba (`never-block-on-the-human`).
- Después de clasificar, el router elige **playbook** según el tipo de tarea.

### Capa 2 — Playbooks (8, no 23)

Cada uno es un `.md` corto: pasos, qué se delega, qué evidencia exige, formato de respuesta.

| Playbook | Origen | Esencia |
|---|---|---|
| `investigate` | pstack | Solo lectura. `path:línea` como evidencia. Distingue hecho, suposición, hueco. |
| `bug` | pstack | Reproducir tú mismo → búsqueda binaria con evidencia de runtime → el commit con el repro que falla va antes del fix → verificar en la misma superficie. Premisa que falló dos veces: se prueba la premisa. |
| `feature` | gentle + uncle-bob | Carril grande: documento de feature, contrato aprobado, test-first por tarea, juez, cierre con evidencia. |
| `refactor` | pstack | Comportamiento preservado. Comparar stdout/stderr/exit code contra HEAD anterior (gentle). Migrar llamadores y borrar la API vieja en la misma ola. |
| `perf` | pstack | Medir línea base; `explain-the-number` antes de creer un resultado. |
| `ship` | gentle + pstack | Commits pequeños y ordenados, Conventional Commits, rebanadas ~400 líneas, PR con cuerpo tipo briefing. Verificación independiente antes de mergear. |
| `babysit` | pstack | Llevar un PR a merge-ready: conflictos, hilos de review, CI. |
| `pickup` | gentle + pstack | Reanudar trabajo previo: leer el documento de feature + Engram, reconciliar con `git diff`. |

Fuera de v1: `prototype`, `hillclimb`, `visual-parity`, `eval`, `autopilot-*`, `orchestrate`, `worktree-cleanup`, `trace-forensics`, `runtime-forensics`.

### Capa 3 — Agentes (3 propios, todos con contexto fresco)

| Agente | Herramientas | Rol | Escribe |
|---|---|---|---|
| `implementer` | lectura + escritura | Una tarea del documento, test-first; recibe **referencia** al documento y las `S#` | código, tests, bitácora de ciclos |
| `judge` | solo lectura + Bash | Aprueba o poda: cobertura de escenarios, disciplina TDD, calidad, `t4l verify` verde | `.t4l/reports/judge_<feature>.md` |
| `reviewer` | solo lectura | Una lente por invocación (`risk`/`reliability`/`readability`/`resilience`), con precision gate, un barrido, ledger de hallazgos | ledger en `.t4l/reports/` |

- Para explorar se usa el `Explore` integrado (devuelve ≤2k tokens con `path:línea`); no hay agente propio.
- El **lead** (la sesión principal) orquesta y verifica. En carril grande no implementa; en carril pequeño sí, inline.
- Un `refuter` no es agente aparte: el `judge` re-verifica los hallazgos graves **solo inferenciales** del `reviewer` antes de aceptarlos.
- La mutación **no es un agente**: es un script determinista; el `judge` interpreta los sobrevivientes.
- Trabajo mecánico y repetitivo (codemods, renombres masivos) se delega a `pi-workers` (ya instalado), no a `implementer`.
- Modelos: Sonnet por defecto; Opus (`high`) solo para `judge` y para diseño en carril grande.

### Capa 4 — Enforcement

| Hook / script | Evento | Qué hace | Origen |
|---|---|---|---|
| `block-ai-attribution` | PreToolUse Bash/Write/Edit | Ya existe. Se conserva. | existente |
| `post-edit-check` | PostToolUse Edit/Write | Corre el comando de test rápido definido en `.t4l/config` y muestra 3 líneas. | uncle-bob |
| `stop-verify` | Stop | Corre `t4l verify` (suite + lint + checks del repo); si falla, lo informa antes de cerrar. | uncle-bob |
| `guard-lead` | PreToolUse Edit/Write | En carril grande, bloquea que el lead edite `src/` y `tests/` (debe delegar). Se activa solo con un marcador en `.t4l/state`. Llega con los agentes (v0.3). | uncle-bob |
| `session-pickup` | SessionStart | Si hay documento de feature abierto, lo recuerda. Engram ya cubre la memoria. Llega con `pickup` (v0.4). | gentle |

Scripts en **POSIX sh** (sin Bun ni binario propio en v1). Configuración por repo en `.t4l/config` (comando de test, de lint, de mutación, umbral).

Decisiones de la v0.2:
- **Opt-in por repo:** los hooks no hacen nada sin `.t4l/config`. Se crea con `/t4l:init`, que detecta Go o TS.
- **Config no ejecutable por clonado:** el archivo se parsea como `KEY=VALUE`, nunca se hace `source` ni `eval`. Si `.t4l/config` está versionado en git, sus comandos no se ejecutan salvo `T4L_TRUST_CONFIG=1`, para que un repo clonado no pueda correr comandos en tu máquina.
- **Rutas seguras:** `{dir}` y `{file}` solo se sustituyen si la ruta tiene caracteres simples (`A-Za-z0-9._/@+-`); si no, el check se omite.
- **Fallo = exit 2:** la salida (últimas 40–60 líneas) llega al agente. El hook `Stop` solo corre con el árbol modificado (sin contar `.t4l/`) y respeta `stop_hook_active` para no entrar en bucle.
- **Apagado:** `disable=1` en la config o `T4L_HOOKS=off`.
- **Tabla regla ↔ enforcer:** vive en el archivo de instrucciones del repo (`CLAUDE.md`, o `AGENTS.md` si no hay), bajo `Rules and enforcers`; la mantiene `/t4l:correct`.

**Skill `correct`** (de pstack, tal cual en espíritu): cuando el usuario corrige dos veces lo mismo, la regla sube al nivel más alto que funcione (arquitectura → tipos → lint con mensaje accionable → test → doc) y se registra en la **tabla regla ↔ enforcer** del repo.

### Capa 5 — Medición
- `CHECKPOINTS` genéricos del estado final (documento de feature coherente, una sola tarea en curso, toda tarea marcada con evidencia, tests verdes, sin código que ningún test pidió).
- 5–10 **journeys** reproducibles (un bug, una feature chica, un refactor, una investigación) para comparar versiones del harness. Se escribe **después** de v0.3, no antes.

## 3. Carril grande en detalle

El carril grande es ODD con documento de feature y espejo en Engram. La puerta humana (pasos 2 y 3) **solo existe si el modo es SDD**; en ODD + TDD el flujo salta del documento directo a las tareas.

```
Pedido autorizado, clasificado GRANDE
  │
  ▼
1. Documento de feature  .t4l/tasks/<feature>.md  + espejo en Engram
     cabecera · ## Specs (S#, textos literales, escenarios Given/When/Then)
     ## Tasks (ID · S# · ruta · commit) · ## Log (L1 = pedido verbatim)
  │
  ▼
2. Conversación de spec — solo decisiones de producto reales, una a la vez
  │
  ▼
3. ⏸ PUERTA HUMANA — se aprueban las Specs/escenarios (el contrato)
  │
  ▼
4. Por tarea:  implementer  ROJO → VERDE → REFACTOR  (hook corre tests)
     commit por unidad (~400 líneas), checkoff solo con evidencia observada
  │
  ▼
5. judge (contexto fresco, solo lectura) — escenario ↔ test, TDD, calidad, verify
     └─ reviewer por lente si el riesgo lo pide; judge re-verifica lo inferencial
  │
  ▼
6. Mutación (solo si la config lo activa para los archivos tocados)
  │
  ▼
7. Cierre: resultado verificado, checks fallidos o pendientes, siguiente paso
```

Un cambio de requisito reescribe solo las `S#` afectadas y reabre solo sus tareas.

## 4. Conflictos entre los tres y cómo se resuelven

| Tema | pstack | gentle-ai | uncle-bob | **t4l** |
|---|---|---|---|---|
| Preguntar al humano | No bloquear en lo reversible | Una pregunta por decisión real | Una puerta sobre el contrato | Una puerta, solo en modo SDD; en lo reversible se prueba y se sigue |
| TDD | Solo si hay test local barato | Test-first por defecto si hay test determinista | Estricto, tres leyes | Modo elegido por el router: test-first cuando hay test determinista ejecutable; tres leyes estrictas dentro de SDD; bug: repro que falla primero |
| Revisión | Multimodelo adversarial | 4 lentes + refuter | Juez único | Juez + `reviewer` por lente; sin multimodelo; diversidad por contexto fresco y lente distinta |
| Mutación | No | No | Obligatoria al 100% de líneas tocadas | Opcional por repo, umbral configurable; activa en módulos críticos |
| Dónde vive el estado | Chat | Documento + Engram | `feature_list.json` + `progress/` | Documento único + Engram + `.t4l/reports/` |
| Rol del lead | Dueño que delega | Inline si es chico | Nunca implementa | Inline en pequeño; solo orquesta en grande |
| Entrada | Manual (`/poteto-mode`) | Automática | Fija en CLAUDE.md | Router automático + `/t4l` explícito |

## 5. Lo que se descarta a propósito

- Cualquier cosa multimodelo, el adaptador de Cursor, Bugbot, Automations.
- Instalador para 17 agentes, telemetría, binario Go, firmas de release.
- RDD / consent ceremony, handoff de defectos del proveedor, preguntas bloqueantes sin pérdida.
- Personas y estilos de salida; skills de video, UI de bots, verificación formal.
- `feature_list.json` y andamiaje docs por repo: lo reemplaza `.t4l/` creado a demanda.

## 6. Integración con lo que ya existe

| Existente | Cómo convive |
|---|---|
| `engram` (plugin) | Memoria y SessionStart; t4l solo guarda decisiones y espeja el documento de feature. |
| `pi-workers` (skill) | Destino de tareas mecánicas/masivas; t4l decide cuándo delegar y revisa el resultado. |
| `block-ai-attribution` (hook) | Invariante del kernel; no se toca. |
| `cc-skills-golang`, `vercel`, `neon`, … | Skills de lenguaje y plataforma; el router los referencia por nombre según el archivo tocado, sin registry propio. |
| `code-review`, `simplify`, `security-review` | Se reutilizan dentro de `ship` y del `reviewer`; no se reimplementan. |

## 7. Forma de distribución

Plugin de Claude Code `t4l` (carpeta `plugin/` con `.claude-plugin/plugin.json`, `skills/`, `agents/`, `hooks/hooks.json`) + un skill `t4l:setup` que instala `rules/t4l.md` en `~/.claude/rules/`, como hace pstack. Marketplace propio en este mismo repo para instalarlo con `/plugin`.

## 8. Decisiones tomadas

| # | Decisión | Resultado |
|---|---|---|
| 1 | Idioma | Harness (reglas, skills, agentes) en inglés. Respuestas en el idioma del último mensaje del usuario; español neutro, sin voseo. |
| 2 | Metodología | ODD como base; TDD y SDD como modos que el router elige según el tipo de tarea (sección 2, "Selector de método"). |
| 3 | Puerta humana | Solo en modo SDD. |
| 4 | Lenguajes de v1 | Go y TypeScript. |
| 5 | Scripts | POSIX sh en v1; un CLI Go solo si los scripts se vuelven frágiles. |
| 6 | Estado por repo | `.t4l/` ignorado por git; documento de feature espejado en Engram. |
| 7 | Alcance de instalación | Global con kernel mínimo; playbooks bajo demanda. |
| 8 | Modelo del `judge` | Opus con esfuerzo alto. `implementer` y `reviewer` con Sonnet. |
| 9 | `guard-lead` | Bloqueo duro con salida de emergencia `T4L_GUARD=off`. Solo cubre Edit/Write, no escrituras por Bash. |
| 10 | Implementadores en v0.3 | Uno a la vez. El paralelismo llega con el `workflow-master` (v0.4). |
| 11 | Explorador | Se usa el `Explore` integrado; no hay agente propio. |
| 12 | `reviewer` | Solo con riesgo alto o más de ~400 líneas, una lente por invocación. |
| 13 | `workflow-master` | v0.4. Kanban solo (sin Scrum). Fusiona en la rama de la feature; el merge a `main` y el push son del usuario. WIP por defecto 2. |

### Pendientes

| # | Pregunta | Recomendación |
|---|---|---|
| A | Mutación | Apagada por defecto; se activa por repo con umbral. Go: `gremlins` o `go-mutesting`. TS: Stryker. |
| B | Comandos por defecto de verificación | Go: `go test ./... && go vet ./...` y `golangci-lint` si existe. TS: el script `test` y `lint` del `package.json` (detecta pnpm/npm/bun). Configurables en `.t4l/config`. |
| C | Skills de lenguaje | Referenciar `cc-skills-golang` para Go; para TS, `vercel:react-best-practices` y `vercel:nextjs` cuando el archivo lo pida. Sin duplicarlos. |

## 9. Hoja de ruta

- **v0.1 — Kernel y router.** `rules/t4l.md` en inglés, skill `t4l` con clasificación, carriles y selector de método (ODD / TDD / SDD), playbooks `investigate` y `bug`.
- **v0.2 — Enforcement (hecha).** Hooks `post-edit-check` y `stop-verify`, `.t4l/config`, `/t4l:init`, `/t4l:correct` y tabla regla↔enforcer. 31 tests de shell (`sh tests/hooks.sh`), `shellcheck` limpio, y comprobado en una ejecución real de Claude Code.
- **v0.3 — Carril grande (en curso).** `scripts/t4l-task.sh` (estado y coherencia del documento de feature), marcador `.t4l/state`, hook `guard` (puerta SDD y lead que no implementa), agentes `implementer`, `judge` y `reviewer`, playbooks `feature`, `refactor` y `ship`. Un implementador a la vez. Las tareas ya llevan `Status`, `Deps` y `Files` para que el tablero de la v0.4 no requiera migrar nada.
- **v0.4 — `workflow-master`.** Ver la sección 10.
- **v0.5 — Medición.** Checkpoints y journeys; mutación opcional; `perf`, `babysit`, `pickup`.
- **v1.0 — Plugin.** Empaquetado, `t4l:setup`, marketplace propio, documentación.

## 10. `workflow-master` (v0.4)

**Propósito acotado:** que varios subagentes trabajen a la vez sin pisarse, que ninguno se salga de su alcance y que las rebanadas de PR no crezcan sin control. No es Scrum: no hay sprints, dailies ni estimaciones. Es un tablero Kanban y tres contratos que se hacen cumplir con scripts y hooks.

### Hallazgos de la prueba técnica

- `isolation: worktree` de la herramienta `Agent` crea el worktree en `<repo>/.claude/worktrees/agent-<id>`, con rama `worktree-agent-<id>`. El `cwd` que ven los hooks es ese worktree y las rutas de `Edit`/`Write` son absolutas dentro de él. El worktree y la rama siguen ahí al terminar si hubo cambios.
- Los nombres no dicen a qué tarea pertenecen, así que la tarea se registra al reclamarla.
- **Fallo latente de la v0.3:** dentro de un worktree, `git rev-parse --show-toplevel` devuelve el worktree, que no contiene `.t4l/`. El `guard` y los hooks de verificación no encontraban `.t4l/state` y no hacían nada. Todo lo que lee estado o configuración debe usar la raíz del checkout principal (`--git-common-dir`); lo que ejecuta comandos usa la raíz del worktree del archivo editado.
- Tras usar worktrees, `.claude/` aparece como no rastreado en el repo principal; `stop-verify` lo excluye.

### Contratos

| Problema | Contrato | Cómo se hace cumplir |
|---|---|---|
| Se pisan entre sí | Cada tarea declara `Files:` (globs) y `Deps:`. En modo paralelo `Files` es obligatorio y dos tareas en `doing` no pueden tener globs que se solapen. Dos globs se solapan si el prefijo estático de uno (hasta el primer `*`, `?` o `[`) es prefijo del otro; es una aproximación conservadora. Los archivos compartidos (`go.mod`, `package.json`, lockfiles) los declara una sola tarea. | `t4l-task.sh start` rechaza el solape y los `Files` vacíos. Cada tarea trabaja en su propio worktree. |
| Se salen del alcance | El agente solo escribe dentro de los `Files` de su tarea. | El hook `guard` mapea el worktree del archivo a su tarea (registro `.t4l/board/<TASK>.env`, escrito por `start`) y deniega fuera de los globs, nombrando a la tarea dueña de esa ruta. Un worktree sin tarea reclamada no puede escribir. |
| PRs demasiado largos | Presupuesto por rebanada (`slice_budget`, por defecto 400 líneas de cambio propio, sin generados ni lockfiles). | `t4l-size.sh` mide una rama contra su base. Un aviso al 80 % (una vez por tarea) y, al superar el presupuesto, el `workflow-master` propone cómo dividir. Es una advertencia, no un tope. |
| La integración falla aunque cada rebanada pase | Se integra en una rama aparte, nunca en `main`. | `t4l-integrate.sh` fusiona las ramas de las tareas en orden de dependencias en un worktree de integración, ejecuta `verify` y `t4l-regress.sh` sobre el resultado fusionado, y mide el tamaño por tarea. El `judge` revisa el árbol integrado. |

### Tablero y modo paralelo

Columnas `todo → doing → review → done`. Límite WIP: 1 en secuencial (v0.3) y 2 en modo paralelo (`wip=` en `.t4l/config`). El modo paralelo lo activa el `workflow-master` con `parallel=1` en `.t4l/state`; con él, un subagente no puede escribir en el checkout principal. `t4l-task.sh board` muestra el tablero con dueños y límites.

### El agente

`t4l:workflow-master` (Sonnet) lo lanza el lead cuando hay dos o más tareas con `Files` disjuntos, o a petición. Puede lanzar `t4l:implementer` en paralelo, cada uno con `isolation: worktree` (comprobado: un subagente puede lanzar otros).

1. Valida el plan: `t4l-task.sh plan-check` lista solapes y archivos compartidos.
2. Tira tareas de `todo` mientras haya hueco WIP y sus dependencias estén en `review` o `done`.
3. Vigila los informes, no los transcripts; al llegar a `review`, mide el tamaño.
4. Integra con `t4l-integrate.sh`; resuelve solo conflictos triviales dentro del worktree de integración y escala el resto.
5. Lanza al `judge` sobre el árbol integrado (`TREE`) y escribe `.t4l/reports/workflow_<feature>.md`.

**Límites de autoridad:** no escribe código de producto (solo `.t4l/` y el worktree de integración), no aprueba specs, no hace merge a `main` ni push. El merge a `main` y el push son del usuario.

**Decisión a vigilar:** en modo paralelo hay commits internos. Cada implementer confirma en su propia rama de tarea (`COMMIT: yes` solo vale para esa rama), `t4l-integrate.sh` hace un commit de instantánea si queda trabajo sin confirmar y crea la rama `t4l/<feature>/integration` con commits de merge. Nada llega a `main` ni a un remoto; son ramas locales desechables. Las tareas dependientes construyen sobre el trabajo de sus dependencias: el implementer fusiona primero sus ramas (`MERGE_FIRST`) y solo entonces hace `start`, para que el tamaño de su rebanada excluya lo ajeno.

**Reutiliza lo que existe:** `isolation: worktree` para los subagentes de Claude y `pi-workers` para el trabajo mecánico masivo.

## 11. Riesgos

- **Sobreingeniería:** vimos tres harnesses grandes. Mitigación: el kernel tiene tope de líneas y cada playbook nuevo debe ganarse su lugar con un journey que falle sin él.
- **Cumplimiento por el modelo:** las reglas en prosa se ignoran. Mitigación: hooks y scripts primero, prosa después.
- **Costo de contexto:** el kernel se carga siempre. Mitigación: tope de 150 líneas y medir tokens por sesión.
- **Mantenimiento de los tres orígenes:** no seguimos sus cambios; tomamos ideas, no código.

## 12. Integraciones opcionales (v0.4.1)

t4l funciona igual sin ellas. El hook `SessionStart` anuncia cuáles están instaladas, porque sin ese anuncio el modelo no sabe que puede usarlas.

### cocoindex-code (`ccc`): búsqueda semántica de código

- **Qué aporta:** consultas conceptuales ("dónde se decide X") contra un índice AST con embeddings locales, en lugar de varias rondas de grep o un `Explore`.
- **Cómo se integra:** con `scripts/t4l-search.sh`, no con el plugin oficial, cuyos hooks reindexan tras cada edición y chocarían con los nuestros.
  - Busca siempre contra el índice del checkout principal, también desde un worktree, y refresca el índice antes de buscar.
  - Es opt-in por repo (`t4l-search.sh --init`) y deja intacto el `.gitignore` versionado: usa `.git/info/exclude`.
  - El índice se refresca en segundo plano al iniciar la sesión.
- **Embeddings:** locales (`[full]`, `Snowflake/snowflake-arctic-embed-xs`, en CPU); el código no sale de la máquina. Configuración global en `~/.cocoindex_code/global_settings.yml`.
- **Medido:** sandbox de 3 archivos, primer índice en 72 s (incluye descargar el modelo), reindexado incremental en 0,4 s, búsqueda en 0,2 s. Clon del harness, 37 archivos en 15 s.
- **Calidad:** buena en código, irregular en shell y Markdown. Sus resultados son **pistas que se verifican leyendo**, nunca evidencia.
- **Excluidos por defecto:** todo directorio oculto (`.t4l/`, `.claude/worktrees/`). `ccc grep` (estructural) no se usa: requiere una versión de cocoindex que aún no se publicó.

### markitdown: documentos a Markdown

- **Qué aporta:** SDD a partir de requisitos en docx, xlsx, pptx, html, epub, msg, etc., con citas literales. Los PDF y las imágenes se leen directamente con `Read`.
- **Cómo se integra:** con `scripts/t4l-ingest.sh` (solo archivos locales; URLs http(s) con `--allow-url`; ningún otro esquema). El resultado va a `.t4l/inputs/<nombre>.md`, con cabecera de procedencia (fuente y sha256) y el aviso de que es dato, no instrucciones.
- **Inyección de prompt:** el script detecta texto con forma de instrucción a un agente, lo marca en la cabecera del archivo convertido y exige mencionarlo al usuario. En la prueba real, el modelo no obedeció la línea inyectada, pero al principio tampoco avisó; con el aviso explícito, avisó.
- **Instalación:** `uv tool install 'markitdown[all]'`.

### Instalación en esta máquina

`uv` 0.13.6 desde el release oficial de GitHub (checksum verificado) en `~/.local/bin`, porque `sudo pacman` pide contraseña. Ambas herramientas instaladas con `uv tool install`.

