"""Spike for #38: keep the history of graph runs as a property graph.

Each run leaves a judge report in the reports directory (the format of
agents/judge.md, plus the "Files changed" list of the implementer report).
CocoIndex turns them into Run and File nodes linked by TOUCHED edges in
FalkorDB, and keeps the graph in step when a report changes or is removed.

    COCOINDEX_DB=state.lmdb python history.py <reports dir> [falkor uri]
"""

import pathlib
import re
import sys
from collections.abc import AsyncIterator
from dataclasses import dataclass

import cocoindex as coco
from cocoindex.connectors import falkordb, localfs
from cocoindex.resources.file import FileLike, PatternFilePathMatcher

REPORTS = coco.ContextKey[pathlib.Path]("reports")
GRAPH = coco.ContextKey[falkordb.ConnectionFactory]("t4l_history")


@dataclass
class Run:
    id: str
    feature: str
    verdict: str


@dataclass
class File:
    path: str


@dataclass
class Touched:
    id: str


@coco.lifespan
async def lifespan(builder: coco.EnvironmentBuilder) -> AsyncIterator[None]:
    builder.provide(REPORTS, pathlib.Path(sys.argv[1]))
    uri = sys.argv[2] if len(sys.argv) > 2 else "falkor://localhost:6390"
    builder.provide(GRAPH, falkordb.ConnectionFactory(uri=uri, graph="t4l_history"))
    yield


def parse(name: str, text: str) -> tuple[Run, list[str]]:
    feature = re.search(r"^# Judge: (.+)$", text, re.M)
    verdict = re.search(r"^Verdict: (\S+)", text, re.M)
    files: list[str] = []
    section = re.search(r"^## Files changed\n((?:- .+\n?)*)", text, re.M)
    if section:
        files = [line[2:].strip() for line in section.group(1).splitlines()]
    run = Run(
        id=name.removesuffix(".md"),
        feature=feature.group(1) if feature else "?",
        verdict=verdict.group(1) if verdict else "?",
    )
    return run, files


@coco.fn(memo=True)
async def process(
    report: FileLike,
    runs: falkordb.TableTarget[Run],
    files: falkordb.TableTarget[File],
    touched: falkordb.RelationTarget[Touched],
) -> None:
    run, paths = parse(report.file_path.path.name, await report.read_text())
    runs.declare_record(row=run)
    for p in paths:
        files.declare_record(row=File(path=p))
        touched.declare_relation(from_id=run.id, to_id=p, record=Touched(id=f"{run.id}:{p}"))


@coco.fn
async def app_main() -> None:
    runs = await falkordb.mount_table_target(
        GRAPH, "Run", await falkordb.TableSchema.from_class(Run, primary_key="id"), primary_key="id"
    )
    files = await falkordb.mount_table_target(
        GRAPH, "File", await falkordb.TableSchema.from_class(File, primary_key="path"), primary_key="path"
    )
    touched = await falkordb.mount_relation_target(
        GRAPH, "TOUCHED", runs, files,
        await falkordb.TableSchema.from_class(Touched, primary_key="id"), primary_key="id",
    )
    reports = localfs.walk_dir(
        REPORTS, path_matcher=PatternFilePathMatcher(included_patterns=["judge_*.md"])
    )
    await coco.mount_each(process, reports.items(), runs, files, touched)


app = coco.App(coco.AppConfig(name="t4l_history"), app_main)

if __name__ == "__main__":
    app.update_blocking(report_to_stdout=True)
