# Spike: base del motor de grafos (#38)

Antes de escribir el motor de grafos (#35) había que responder cuatro preguntas. Las responde este spike con prototipos descartables y mediciones, no con el motor. Los prototipos están en `spikes/graph/` y quedan fuera del zip del plugin.

Entorno de las mediciones: WSL2, 10 núcleos, 7 GB de RAM, sin GPU, Go 1.27.3, ADK Go v2.6.0, cocoindex 1.0.26, cocoindex-code 0.2.42 con `Snowflake/snowflake-arctic-embed-xs` en CPU. Fecha: 2026-10-29.

## Resumen

| Pregunta | Respuesta |
|---|---|
| 1. ¿ADK Go como dependencia? | **Sí.** Los nodos de función corren sin modelo. Una ejecución se pausa en un nodo `human` y se reanuda en otro proceso desde SQLite. Los ciclos con máximo de intentos se pueden modelar. Va detrás de un paquete propio para poder cambiarlo. |
| 2a. ¿CocoIndex como contexto de los nodos `agent`? | **Sí, con lo que ya existe.** `scripts/t4l-search.sh` ya integra `ccc` de forma opcional. El motor lo llamaría al armar el brief, con filtros de lenguaje y ruta por nodo. |
| 2b. ¿CocoIndex como memoria del grafo, con consultas entre repositorios? | **Sí, con SQLite como destino y no con una base de grafos.** El motor escribe un registro por ejecución en un almacén por usuario, fuera de los repos, al que solo se agregan registros. CocoIndex lo proyecta a SQLite. Las cuatro consultas entre repos dieron las mismas filas en SQLite y en FalkorDB, con tiempos parecidos, y SQLite no necesita servidor. |
| 3. ¿Cómo viaja el binario? | **Binarios por plataforma adjuntos al release, descargados en el primer uso con checksum.** Compilar al instalar exige Go, tarda 25 s y descarga 1,1 GB de módulos. |
| 4. ¿Grafos por repositorio? | **No en v2.0.** CocoIndex no lo exige: los filtros de búsqueda son configuración de cada nodo, y vienen compilados con el harness. |

## 1. ADK Go `workflow` como dependencia

**Prototipo** (`spikes/graph/adk/main.go`, unas 250 líneas): una versión chica del carril grande.

```
plan -> approve (human) -> implement (agent) -> judge -+-> ship
              |                 ^                      |
              +-> rejected      +------ fail ----------+
                                judge -> escalate   (fail con el máximo de intentos)
```

Cada comando (`start`, `status`, `resume`) es un proceso aparte. La sesión vive en SQLite (`session/database` sobre `github.com/glebarez/sqlite`, sin cgo).

**Resultados:**

- **Nodos sin modelo:** `NewFunctionNode` y `NewEmittingFunctionNode` corren sin modelo ni clave de API. ADK trae ejemplos así (`examples/workflow/hitl_simple`).
- **Pausa y reanudación entre procesos:** funcionan.
  - `start` corre hasta `approve`. Ese nodo usa `workflow.ResumeOrRequestInput` con `RerunOnResume` y emite un `RequestInput`.
  - `status`, en otro proceso, lee la pregunta pendiente de los eventos guardados.
  - `resume yes`, en un tercer proceso, manda un `FunctionResponse` con el ID de la interrupción. La ejecución sigue: `Workflow.ReconstructRunState` la rearma desde los eventos de la sesión.
- **Salidas tipadas:** el struct `Work` vuelve con sus tipos después del viaje por SQLite.
- **Ciclos:** la validación solo rechaza los ciclos incondicionales (`ErrUnconditionalCycle`), así que `judge -> implement` con la ruta `fail` es válido. El máximo de intentos no existe como concepto en ADK: lo lleva el nodo, con un contador en la salida. Los tres escenarios (`fail,pass` → `ship`, `fail,fail` → `escalate`, plan rechazado → `rejected`) dieron lo esperado.
- **Nodo `agent`:** un nodo de función que ejecuta `claude -p` funciona. El `resume` con una llamada real tardó 6,8 s, casi todo de `claude`.
- **Una trampa:** un nodo que emite el evento con `Routes` y `Output` tiene que devolver `nil`. Si devuelve también un valor, ADK falla con "node produced multiple events with output values".

**Costos y riesgos:**

| | Medición |
|---|---|
| Módulos en el grafo de dependencias | 141 (genai, OpenTelemetry, gorm, modernc sqlite, entre otros) |
| Paquetes compilados | 328 |
| Binario `linux/amd64` con `-s -w` | 20 MB (entre 19 y 21 MB según la plataforma) |
| Compilación en frío | 25 s y 1,1 GB de caché de módulos |

- La API v2 es joven: de v2.2.0 a v2.6.0 en poco tiempo.
- El modelo de sesión está pensado para chat. La aprobación humana viaja como un `FunctionResponse` con el nombre `adk_request_input`, y hace falta app, usuario y sesión aunque t4l tenga un solo usuario.

**Recomendación:** usar ADK Go con la versión fijada, detrás de un paquete propio (`internal/graph`) que exponga solo lo que usa t4l: los cuatro tipos de nodo, rutas, `max`, `start`, `status` y `next`. Así el resto del harness no depende de ADK. La sesión va en `.t4l/graph.db`.

El cambio a un motor propio con la misma forma se decide si pasa cualquiera de estas dos cosas: una versión rompe el paquete propio sin dar algo a cambio, o el peso de las dependencias complica los builds de release.

## 2. CocoIndex junto con el grafo

### 2a. Contexto para los nodos `agent` (cocoindex-code)

**Lo que ya existe:** `scripts/t4l-search.sh` ya integra `ccc`, y el implementer lo usa cuando el checkout principal tiene `.cocoindex_code/`. El script ya resuelve varias cosas:

- Funciona desde un worktree.
- Deja intacto el `.gitignore` versionado.
- Refresca el índice antes de buscar.
- Devuelve el código 3 si `ccc` no está habilitado, así que es opcional.

**Mediciones** (`ccc index` y `ccc search --json` sobre copias de los repositorios):

| Repositorio | Archivos | Chunks | Primer índice | Reíndice sin cambios | Reíndice con un archivo editado | Búsqueda |
|---|---|---|---|---|---|---|
| t4l-harness | 89 (64 indexados) | 515 | 44 s (incluye arrancar el daemon y cargar el modelo) | 0,3 s | 0,3 s | 0,1 s |
| ADK Go v2.6.0 | 1092 (969 indexados) | 21 201 | 12 min 3 s | 1,6 s | 1,3 s | 1,0 s |

- **Calidad:** cada resultado trae `file_path`, `start_line`, `end_line`, `content` y `score`, que es lo que necesita un brief.
  - Sin filtros, la documentación le gana al código. A "which files is the judge allowed to write during a protected phase" respondió primero con `skills/t4l/playbooks/feature.md`, `docs/references.md` y `docs/design.md`.
  - Con `--lang bash`, `hooks/guard.sh` sale primero, seguido de los casos de `tests/hooks.sh`.
  - Conclusión: cada nodo tiene que traer sus propios filtros de lenguaje y de ruta.
- **Un solo daemon:** hay un daemon de `ccc` para todos los proyectos, y mientras indexa uno, las búsquedas de otro esperan. Una búsqueda en t4l quedó bloqueada mientras se indexaba ADK Go.
- **Instalación:** `cocoindex-code[full]` instalado con `uv tool` ocupa 5,9 GB, sobre todo por PyTorch, y el modelo 88 MB más. Por eso no puede ser obligatorio.

**Recomendación:** el motor no agrega runtime. Cuando arma el brief de un nodo `agent`, llama a `t4l-search.sh` con la consulta y los filtros del nodo. Por ejemplo, `implement` busca el concepto de la tarea limitado a los `Files` de la tarea, y `judge` busca los tests de los escenarios. Pega los primeros resultados como pistas a verificar.

Si el script devuelve 3, el brief sale sin esa sección. El `--refresh` en cada transición cuesta menos de 2 s incluso en el repositorio grande. Lo caro es el primer índice, y ese se hace una sola vez con `t4l-search.sh --init`, que `/t4l:setup` ya sugiere cuando `ccc` está instalado.

### 2b. Memoria del grafo, entre repositorios (núcleo de CocoIndex)

Hacen falta consultas entre repositorios. La primera versión de esta sección las postergaba; este es el análisis completo.

**Primer prototipo, un solo repo** (`spikes/graph/coco/history.py`, con la API v1: `@coco.fn`, `coco.App`, `mount_each`): lee los `judge_*.md` con el formato de `agents/judge.md` más la lista "Files changed" del implementer, y escribe `Run -[TOUCHED]-> File` en FalkorDB.

- **Funciona:** la consulta por `hooks/guard.sh` devolvió los dos intentos de bash-guard con su veredicto.
- **Incremental:** sin cambios no reprocesa nada. Un reporte editado se reprocesa solo, y un reporte borrado elimina su `Run` y los `File` que quedan huérfanos.
- **Estado:** CocoIndex guarda el suyo en un archivo LMDB local (`COCOINDEX_DB`). No necesita Postgres.

**La fuente no puede ser `.t4l/reports`.** `judge_<feature>.md` se sobrescribe cada vez que el judge vuelve a correr sobre una feature, y `.t4l/` no está versionado, así que se pierde con el clon. Como CocoIndex refleja en el destino lo que desaparece de la fuente, el historial se perdería con ellos. Por eso la fuente de verdad es un almacén por usuario, fuera de los repos, donde cada ejecución deja un registro que nunca se reescribe:

```
<almacén>/runs/<repo>/<id>.json   {"run", "feature", "verdict", "attempts", "files": [...]}
```

**Segundo prototipo, varios repos** (`history_multi.py`, `query_multi.py`, `make_store.py`): la misma fuente proyectada a dos destinos, FalkorDB (`Repo`, `Run`, `File` y las aristas `IN` y `TOUCHED`) y SQLite (tablas `runs` y `touched`). Se hacen las mismas cuatro preguntas en Cypher y en SQL:

1. Quién tocó una ruta, en cualquier repo.
2. Qué rutas se tocaron en más de un repo.
3. La tasa de rechazo y los intentos promedio por repo.
4. Qué rutas tuvieron un rechazo en un repo y también se tocaron en otro (dos saltos).

Con tres repos de ejemplo, y luego con 20 repos de 500 ejecuciones cada uno (10 000 registros y unos 45 000 archivos tocados, de los cuales cinco rutas se comparten entre todos los repos), **los dos destinos devolvieron exactamente las mismas filas en las cuatro preguntas**.

| Con 10 000 ejecuciones | FalkorDB | SQLite |
|---|---|---|
| Carga inicial | 57 s | 34 s |
| Actualización sin cambios, o agregando una ejecución | 10 a 11 s | 10 s |
| Modo `live` (un proceso que vigila el almacén) | no aplica, ver abajo | la ejecución nueva o borrada se refleja en 0,05 s; el proceso ocupa unos 92 MB |
| Consultas 1 a 4, con índice sobre `path` | 23 ms, 24 ms, 7 ms, 30 ms | 4 ms, 12 ms, 2 ms, 33 ms |
| Runtime aparte | contenedor (imagen de 734 MB, 166 MB de RAM) | ninguno: un archivo de 8 MB |
| Estado de CocoIndex | 44 MB | 26 MB |

Lo que salió mal, y por qué pesa en la decisión:

- **Los nodos compartidos del grafo fallan en silencio.** En la primera carga a FalkorDB, cada ejecución declaraba su `Repo` y sus `File`. Muchas ejecuciones declaran los mismos nodos (`go.mod`, el repo), así que compiten por ser dueñas de cada uno ("pre_commit gave up after 8 retries waiting for concurrent ownership transfer"). El 73 % de los registros falló y **el proceso terminó con código 0**.
  - Sin declarar esos nodos, las aristas los crean solas con `MERGE`, pero quedan solo con `id`, sin `path`. Las consultas fueron rápidas porque no devolvían nada.
  - La forma correcta es la del ejemplo "docs to knowledge graph" de CocoIndex: una fase lee cada registro (`coco.map`) y un solo componente declara los nodos compartidos ya deduplicados. Esa forma no admite el modo `live`, que necesita un componente por archivo (`mount_each`).
  - En SQLite el problema no existe, porque cada fila pertenece a una sola ejecución.
- **La consulta de dos saltos depende de cómo se escribe**, no del destino. Escrita de forma ingenua, cruzaba todas las ejecuciones que tocaron `go.mod` contra todas las demás, y agotó el tiempo en FalkorDB y tardó 2,3 s en SQLite. Deduplicando primero por ruta y repo, bajó a unos 30 ms en los dos.
- **Sin modo `live`, cada actualización cuesta unos 10 s con 10 000 ejecuciones**, porque CocoIndex recorre el almacén entero. Con el modo `live`, el cambio se refleja casi al instante.

Hay otra opción, que el motor escriba en SQLite directamente desde Go: sin Python y con la fila disponible al instante. Si con eso alcanza, CocoIndex no aporta nada a las consultas estructuradas. Donde sí aporta es en lo que esa opción no cubre:

- **Más fuentes:** además de los registros del motor, puede leer specs y reportes en Markdown de cada repo.
- **Una proyección que se reconstruye:** si se corrige o se borra un registro, el destino se actualiza con él.
- **Embeddings en el mismo pipeline:** el conector SQLite tiene tablas `vec0`. Con eso se podría buscar por similitud entre repos, por ejemplo "¿ya resolvimos algo parecido en otro repo?". `ccc` no lo hace, porque indexa cada proyecto por separado. Esto **no se probó** en el spike.

**Recomendación:**

- **Almacén:** `${XDG_DATA_HOME:-~/.local/share}/t4l/runs/<repo>/<id>.json`, escrito por el motor al cerrar cada ejecución. El registro lleva nodos recorridos, rutas, intentos, veredictos y archivos tocados. El almacén no va en `CLAUDE_PLUGIN_DATA`: ese directorio pertenece a la instalación del plugin, y el historial es del usuario, independiente de cómo esté instalado t4l.
- **Identidad del repo:** no puede ser el nombre de la carpeta, porque dos clones pueden llamarse igual. Hace falta un identificador estable, por ejemplo la URL de `origin` normalizada o el hash del primer commit.
- **Proyección:** CocoIndex hacia `history.db` (SQLite), en el mismo directorio que el almacén. Por defecto se actualiza en segundo plano al cerrar cada ejecución. El modo `live` queda como opción para quien lo quiera siempre al día.
- **Consultas:** `t4l history` en el binario de Go lee `history.db`; Go ya tiene SQLite por ADK. Trae las cuatro preguntas del prototipo como subcomandos y permite SQL libre para el resto.
- **Sin CocoIndex:** el almacén se sigue escribiendo, y `t4l history` avisa cómo habilitarlo.
- **Sin base de grafos por ahora:** FalkorDB no respondió nada que SQL no respondiera, y agrega un contenedor, la restricción de las dos fases y el riesgo de fallar con código 0. Se reconsidera si aparecen consultas de muchos saltos que en SQL se vuelvan ilegibles.

### La frontera entre Go y Python

| Uso | Frontera |
|---|---|
| Contexto de los nodos | El CLI, a través de `t4l-search.sh`, que ya existe y es opcional. |
| Historial | El motor escribe JSON en el almacén. CocoIndex, un proceso aparte, lo proyecta a SQLite. El motor solo lee `history.db`. |

El MCP de `ccc` no hace falta para el motor: el lead y los subagentes ya pueden usar `ccc` por el script.

## 3. Cómo viaja el binario

| Opción | Medición |
|---|---|
| Binarios de release (`CGO_ENABLED=0`, `-trimpath -ldflags='-s -w'`) | Cinco plataformas compilan sin cgo: linux y darwin en amd64 y arm64, más windows/amd64. Entre 19 y 21 MB cada uno y entre 10 y 17 s de compilación cada uno. |
| `go build` al instalar | Exige Go en la máquina del usuario, tarda 25 s en frío y descarga 1,1 GB de módulos. |

**Recomendación:** el job `publish` de `release.yml` adjunta un binario por plataforma y un archivo de checksums. Al primer uso, un `t4l graph` en sh detecta el sistema y la arquitectura, descarga el binario de la versión de `plugin.json`, verifica el checksum y lo guarda en `CLAUDE_PLUGIN_DATA`, el mismo lugar donde `t4l-version.sh` guarda su caché.

El zip no incluye los binarios: los cinco pesarían unos 100 MB. Las actualizaciones automáticas siguen funcionando, porque una versión nueva de `plugin.json` dispara una descarga nueva.

## 4. Grafos por repositorio

CocoIndex no obliga a definir grafos por proyecto. Las fuentes del índice de código son el repositorio mismo, y los filtros de búsqueda son configuración de cada nodo. Para v2.0, los grafos vienen compilados con el harness, como estaba previsto. Si más adelante un repositorio necesita, por ejemplo, otro verificador o lentes de revisión distintas, se puede agregar configuración por nodo en `.t4l/config` sin redefinir el grafo.

## Cambios para #35

- La dependencia es ADK Go v2, con la versión fijada, detrás de `internal/graph`. La sesión va en `.t4l/graph.db`.
- El máximo de intentos va en la salida de cada nodo. ADK no lo trae.
- El brief de los nodos `agent` incluye los resultados de `t4l-search.sh` con filtros por nodo, si está habilitado.
- El motor escribe un registro por ejecución en `${XDG_DATA_HOME:-~/.local/share}/t4l/runs/<repo>/<id>.json`, con un identificador estable de repo. CocoIndex lo proyecta a `history.db` (SQLite), y `t4l history` lo consulta entre repos.
- Los binarios por plataforma se adjuntan al release y se descargan en el primer uso con checksum.
