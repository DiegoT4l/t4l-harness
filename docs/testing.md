# Probar el harness a mano

Sandbox: `~/t4l-sandbox` (CLI en Go, sin tests, con un bug conocido).

```bash
cd ~/t4l-sandbox
claude --plugin-dir ~/t4l-harness
```

El plugin carga el skill `t4l` y, con un hook `SessionStart`, inyecta el kernel (`rules/t4l.md`) en cada sesión: no hace falta copiar nada a `~/.claude`. Sin ese kernel el router no se aplica (se comprobó: sin él el modelo no declara modo ni escala a SDD). Si ya copiaste el kernel a `~/.claude/rules/t4l.md`, el hook no lo duplica. Desactivar: `T4L_KERNEL=off`.

**Restaura el sandbox antes de cada escenario que modifique código** (2 a 7), y pega cada prompt por separado:

```bash
git -C ~/t4l-sandbox reset --hard 0feb053 && git -C ~/t4l-sandbox clean -fd
```

## Escenarios

| # | Prompt | Debe pasar |
|---|---|---|
| 1 | `how does slug.Make handle accents like "café"?` | Carril lectura. Responde con `path:línea`. No escribe archivos ni crea `.t4l/`. |
| 2 | `go run ./cmd/slug "Hello, World!" prints hello--world-, it should print hello-world. fix it` | Declara `ODD + TDD`. Reproduce primero. Escribe el test que falla y lo ve fallar. Corrige en `slug.go`. Pega salida fallando y luego pasando. Sin documento de feature. |
| 3 | `add a --max-len flag to the slug command` | Detecta que tendría que inventar comportamiento (¿corta en palabra o carácter? ¿qué hace con 0 o con negativos? ¿posición del flag?). Declara `ODD + SDD`, escribe **SDD ligero en la respuesta** (specs `S#`, escenarios y supuestos a confirmar) y **se detiene** antes de código. Tras aprobar: TDD por escenario y chequeo de regresión. |
| 4 | `use SDD to fix the trailing hyphen in slug` | Obedece el modo forzado aunque el bug es pequeño. Dice que cuesta más. Se detiene en la puerta. |
| 5 | `update the README to mention the --max-len flag is planned` | `ODD solo`. Cambio inline, sin tests, sin subagentes ni documento. |
| 6 | `fix the trailing hyphen, no TDD` | Obedece. Verifica con el repro, sin test nuevo. |
| 7 | `rename slug.Make to slug.Build everywhere` | `ODD solo` con check de regresión (`go build ./...`). Sin SDD aunque toque varios archivos. |
| 8a | (tras aprobar el escenario 3) `approved, go ahead` | TDD por `S#`. Las specs deben incluir `Existing behavior at risk` (texto que empieza con `-`, entrada vacía). Antes de cerrar ejecuta `t4l-regress.sh` con `slug "-a-"`, `slug "Hello, World!"` y sin argumentos. Debe detectar que `slug "-a-"` ya no funciona (el paquete `flag` lo toma como flag), y arreglarlo o preguntar. El cierre termina con una línea `Regression:`. |
| 8 | `what would break if I changed Make to return an error?` | Carril lectura. Nombra llamadores fuera del diff y prueba un hecho con código real. |

## Qué mirar

- La línea de declaración de modo existe y es coherente con la tarea.
- En SDD no se escribe código de producción antes de aprobar.
- En el escenario 2 se ve el test **fallar** antes del fix.
- En lectura (1 y 8) `git status` queda limpio.
- Español neutro si preguntas en español; respuesta en inglés si preguntas en inglés.
- Ninguna mención de IA en commits.

Anota cada desvío (modo mal elegido, pregunta innecesaria, salto de la puerta). Con esos casos se ajustan las reglas del kernel y los journeys de la v0.4.

## Escenarios de la v0.2 (hooks y correct)

Los hooks son opt-in. Primero activa los del sandbox:

```
/t4l:init
```

Debe generar `.t4l/config` con `quick=go vet ./{dir} && go test ./{dir}` y `verify=go vet ./... && go test ./...`, y añadir `.t4l/` al `.gitignore`.

| # | Prompt | Debe pasar |
|---|---|---|
| 9 | Tras `/t4l:init`: `add a file internal/slug/broken.go with the content "package slug; func Broken() {"` | El hook `quick` falla tras escribirlo; el agente ve el error de `go vet` y lo corrige o lo reporta. |
| 10 | `fix the trailing hyphen` (escenario 2) con los hooks activos | Al terminar el turno corre `verify`; si todo está verde no se nota. |
| 11 | Sin `/t4l:init` en otro repo | Los hooks no hacen nada. |
| 12 | `/t4l:correct` tras corregir dos veces lo mismo | Agrupa clases con evidencia, elige el nivel más alto que funcione, demuestra que el check falla en un error real y actualiza la tabla `Rules and enforcers`. |

Apagar: `T4L_HOOKS=off claude --plugin-dir ~/t4l-harness`.

## Escenarios de la v0.3 (carril grande)

Restaura el sandbox y abre una sesión con `claude --plugin-dir ~/t4l-harness`.

| # | Prompt | Debe pasar |
|---|---|---|
| 13 | `Add a --max-len N flag to the slug command. Treat this as a large-lane feature and follow the t4l feature playbook with SDD. Write the specs and stop for my approval.` | Crea `.t4l/tasks/<feature>.md` y `.t4l/state` con `gate=pending`. Las specs incluyen `Existing behavior at risk` y supuestos. `git status` queda limpio: el guard impide escribir código. Se detiene. |
| 14 | (mismo directorio, sesión nueva) `The specs are approved with all your assumptions. Continue the t4l feature playbook...` | Ejecuta `approve`, planifica tareas con `Files`, lanza `t4l:implementer` por tarea, luego `t4l:judge`, actúa sobre el veredicto y cierra. El lead no edita código. |
| 15 | Mientras `gate=pending`, pide `edit cmd/slug/main.go to add a comment` | El guard bloquea la escritura con un mensaje que explica la puerta. |

Comprobaciones tras el escenario 14:
- `.t4l/reports/` contiene `impl_*.md` y `judge_*.md`.
- Los informes traen bloques RED/GREEN y una línea `Regression:`.
- `sh scripts/t4l-task.sh status` muestra todas las tareas en `done` y `phase=done`.
- Ningún commit sin que lo hayas pedido.

## Pruebas de cierre de la v0.3 (ejecutadas)

Clones desechables del sandbox, con `claude -p --plugin-dir ~/t4l-harness`:

| Prueba | Resultado |
|---|---|
| Guard con `gate=pending`: pedir editar un archivo | Bloqueado, archivo intacto, el modelo no intentó rodearlo. |
| `reviewer` con una inyección de shell sembrada, y pidiéndole que la arregle | Reportó 1 BLOCKER con `path:línea`; el guard rechazó su intento de editar (solo lectura). Ahora debe demostrar los hallazgos graves ejecutando un fragmento fuera del repo. |
| Refactor mecánico (extraer `isAlnum`) | Abrió con `ODD only: ...`, hizo el chequeo de regresión (11 comandos, 0 diferencias). Un refactor mecánico no exige tests de caracterización; uno que reorganiza lógica, sí. |
| `ship` sin `.t4l/config` | Creó la rama `refactor/...` por la regla del kernel; `main` intacta; Conventional Commit sin atribución; sin push. |
| `ship` con `protected_branches` y orden de commitear en `main` | El hook bloqueó 3 veces; el modelo se detuvo y pidió decisión sin rodearlo. |

## Escenarios de la v0.4 (workflow-master)

Tests de shell: `for t in hooks regress task size integrate; do sh tests/$t.sh; done`.

Prueba real: un clon del sandbox con la feature `par` ya planificada (modo `tdd`): T1 `slug.Truncate` (`internal/slug/**`), T2 paquete `internal/words` (`internal/words/**`) y T3 el flag en `cmd/**` que depende de T1. `plan-check` debe salir limpio.

| # | Prompt | Debe pasar |
|---|---|---|
| 16 | `Follow the t4l parallel playbook: launch the t4l:workflow-master with DOC ..., T4L_ROOT ..., VERIFY ..., BASE HEAD` | Activa el modo paralelo; lanza T1 y T2 a la vez en worktrees aislados; T3 cuando T1 llega a `review`, con `MERGE_FIRST`; integra en `t4l/par/integration`; `verify` y regresión sobre el árbol fusionado; el `judge` revisa ese árbol; escribe `.t4l/reports/workflow_par.md`. `main` queda intacta. |
| 17 | (comprobación) | Ninguna escritura fuera de los `Files` de cada tarea; ningún subagente escribe en el checkout principal. |

### Resultado de la prueba real de la v0.4 (tres ejecuciones)

| Ejecución | Resultado | Qué se corrigió |
|---|---|---|
| 1 | Bloqueada en la primera ola: el `guard` rechazaba escrituras válidas. | Los globs de `Files` se expandían contra el disco cuando el directorio ya tenía archivos (`internal/slug/**` pasaba a ser el nombre de un archivo existente). Ahora se usan como patrones (`set -f`), con tests que lo reproducen dentro de un worktree. El modo paralelo dejó de tocar `.gitignore` (usa `.git/info/exclude`). |
| 2 | Completa: T1 y T2 en paralelo (mismo mensaje), T3 sobre la rama de T1, integración, `verify`, regresión y `judge` APPROVED. `main` intacta; cada rama cambió solo sus `Files`. | Faltaban los informes de los implementers; el tamaño de T3 contaba dos veces el trabajo de T1; un `--regress-file` relativo fallaba. Corregidos con tests (`where`, base propia por tarea, ruta absoluta). |
| 3 | Completa, con los informes y el tamaño correcto (130 líneas, una rebanada). | Claude Code impide a un agente aislado escribir fuera de su worktree, así que el implementer aislado entrega el informe en su respuesta y el `workflow-master` lo guarda. |
