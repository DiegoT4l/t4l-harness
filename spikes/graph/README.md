# Graph engine spike (#38)

Throwaway prototypes behind [`docs/spikes/graph-engine.md`](../../docs/spikes/graph-engine.md). They are not part of the harness and never go into the plugin zip: `scripts/t4l-package.sh` packages a fixed list of directories, and `spikes/` is not one of them.

## `adk/`: the large lane on ADK Go v2

The graph `plan -> approve (human) -> implement (agent) -> judge -> ship | implement | escalate`. Each command runs as a separate process, and the run is stored in SQLite.

```sh
cd adk
go run . -db run.db start "login form"   # stops at approve
go run . -db run.db status               # the pending question, read back from SQLite
T4L_SPIKE_VERDICTS=fail,pass go run . -db run.db resume yes
```

`T4L_SPIKE_CLAUDE=1` makes `implement` call `claude -p`.

## `coco/`: the run history as a property graph

A CocoIndex app that turns judge reports into `Run -[TOUCHED]-> File` in FalkorDB, plus a query: which past runs touched a file, and what the judge said.

```sh
docker run -d --name t4l-spike-falkor -p 127.0.0.1:6390:6379 falkordb/falkordb:latest
uv venv coco-venv --python 3.12 && uv pip install --python coco-venv/bin/python "cocoindex[falkordb]"
COCOINDEX_DB=state.lmdb coco-venv/bin/python coco/history.py <reports dir>
coco-venv/bin/python coco/query.py hooks/guard.sh
```
