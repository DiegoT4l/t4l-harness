"""Spike for #38: the run history across repositories.

Runs from every repository land in one store per user, never inside a
repository: <store>/runs/<repo>/<run>.json. Records are only ever added,
because .t4l/ is not versioned and a judge report is overwritten when the
judge runs again. CocoIndex projects the store into a graph or into SQLite
tables, and keeps it in step with the store.

    COCOINDEX_DB=state.lmdb python history_multi.py falkor <store> [falkor uri]
    COCOINDEX_DB=state.lmdb python history_multi.py sqlite <store> <db file>

A record: {"run", "feature", "verdict", "attempts", "files": [...]}.
"""

import json
import os
import pathlib
import sys
from collections.abc import AsyncIterator
from dataclasses import dataclass

import cocoindex as coco
from cocoindex.connectors import falkordb, localfs, sqlite
from cocoindex.resources.file import FileLike, PatternFilePathMatcher

BACKEND = sys.argv[1]
LIVE = os.environ.get("T4L_SPIKE_LIVE") == "1"
STORE = coco.ContextKey[pathlib.Path]("store")
GRAPH = coco.ContextKey[falkordb.ConnectionFactory]("t4l_history_graph")
DB = coco.ContextKey[sqlite.ManagedConnection]("t4l_history_db")


@dataclass
class Repo:
    name: str


@dataclass
class Run:
    id: str
    repo: str
    feature: str
    verdict: str
    attempts: int


@dataclass
class File:
    id: str
    repo: str
    path: str


@dataclass
class Edge:
    id: str


@dataclass
class Touched:
    run: str
    file: str
    repo: str
    path: str


@coco.lifespan
async def lifespan(builder: coco.EnvironmentBuilder) -> AsyncIterator[None]:
    builder.provide(STORE, pathlib.Path(sys.argv[2]))
    if BACKEND == "falkor":
        uri = sys.argv[3] if len(sys.argv) > 3 else "falkor://localhost:6390"
        builder.provide(GRAPH, falkordb.ConnectionFactory(uri=uri, graph="t4l_history"))
    else:
        builder.provide(DB, sqlite.connect(sys.argv[3]))
    yield


def load(report: FileLike, text: str) -> tuple[Run, list[File]]:
    rec = json.loads(text)
    repo = report.file_path.path.parent.name
    run = Run(
        id=f"{repo}/{rec['run']}",
        repo=repo,
        feature=rec["feature"],
        verdict=rec["verdict"],
        attempts=rec.get("attempts", 1),
    )
    files = [File(id=f"{repo}:{p}", repo=repo, path=p) for p in rec.get("files", [])]
    return run, files


@dataclass
class Record:
    run: Run
    files: list[File]


@coco.fn(memo=True)
async def read_record(report: FileLike) -> Record:
    run, fs = load(report, await report.read_text())
    return Record(run=run, files=fs)


@coco.fn
async def build_graph(
    recs: list[Record],
    repos: falkordb.TableTarget[Repo],
    runs: falkordb.TableTarget[Run],
    files: falkordb.TableTarget[File],
    in_repo: falkordb.RelationTarget[Edge],
    touched: falkordb.RelationTarget[Edge],
) -> None:
    # Repo and File nodes are shared by many runs, so one component declares
    # each of them once. Declared from every run, the runs compete for
    # ownership and most of the first load fails, with exit status 0.
    shared: dict[str, File] = {}
    for rec in recs:
        runs.declare_record(row=rec.run)
        in_repo.declare_relation(from_id=rec.run.id, to_id=rec.run.repo, record=Edge(id=rec.run.id))
        for f in rec.files:
            shared[f.id] = f
            touched.declare_relation(from_id=rec.run.id, to_id=f.id, record=Edge(id=f"{rec.run.id}>{f.id}"))
    for name in {rec.run.repo for rec in recs}:
        repos.declare_record(row=Repo(name=name))
    for f in shared.values():
        files.declare_record(row=f)


@coco.fn(memo=True)
async def to_tables(
    report: FileLike,
    runs: sqlite.TableTarget[Run],
    touched: sqlite.TableTarget[Touched],
) -> None:
    run, fs = load(report, await report.read_text())
    runs.declare_row(row=run)
    for f in fs:
        touched.declare_row(row=Touched(run=run.id, file=f.id, repo=f.repo, path=f.path))


def records() -> localfs.DirWalker:
    return localfs.walk_dir(
        STORE, recursive=True, live=LIVE,
        path_matcher=PatternFilePathMatcher(included_patterns=["runs/*/*.json"]),
    )


@coco.fn
async def app_main() -> None:
    if BACKEND == "falkor":
        def schema(cls, pk):
            return falkordb.TableSchema.from_class(cls, primary_key=pk)
        repos = await falkordb.mount_table_target(GRAPH, "Repo", await schema(Repo, "name"), primary_key="name")
        runs = await falkordb.mount_table_target(GRAPH, "Run", await schema(Run, "id"), primary_key="id")
        files = await falkordb.mount_table_target(GRAPH, "File", await schema(File, "id"), primary_key="id")
        in_repo = await falkordb.mount_relation_target(
            GRAPH, "IN", runs, repos, await schema(Edge, "id"), primary_key="id")
        touched = await falkordb.mount_relation_target(
            GRAPH, "TOUCHED", runs, files, await schema(Edge, "id"), primary_key="id")
        recs = await coco.map(read_record, records())
        await coco.mount(
            coco.component_subpath("build_graph"), build_graph, recs, repos, runs, files, in_repo, touched)
    else:
        runs = await sqlite.mount_table_target(
            DB, "runs", await sqlite.TableSchema.from_class(Run, primary_key=["id"]))
        touched = await sqlite.mount_table_target(
            DB, "touched", await sqlite.TableSchema.from_class(Touched, primary_key=["run", "file"]))
        await coco.mount_each(to_tables, records().items(), runs, touched)


app = coco.App(coco.AppConfig(name=f"t4l_history_{BACKEND}"), app_main)

if __name__ == "__main__":
    app.update_blocking(report_to_stdout=not LIVE, live=LIVE)
