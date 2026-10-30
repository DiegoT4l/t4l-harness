"""Spike for #38: find a problem already solved in another repository.

Each run record in the store carries a summary of what was solved and how.
CocoIndex embeds "feature: summary" and keeps the vectors in SQLite next to
the record, so a new task can be matched against every repository.

    COCOINDEX_DB=state.lmdb python semantic.py <store> <db file> <model>

Needs sentence-transformers and sqlite-vec, which the cocoindex-code tool
environment already has.
"""

import json
import os
import pathlib
import sys
from collections.abc import AsyncIterator
from dataclasses import dataclass

import numpy as np
from numpy.typing import NDArray

import cocoindex as coco
from cocoindex.connectors import localfs, sqlite
from cocoindex.ops.sentence_transformers import SentenceTransformerEmbedder
from cocoindex.resources.file import FileLike, PatternFilePathMatcher

STORE = coco.ContextKey[pathlib.Path]("store")
DB = coco.ContextKey[sqlite.ManagedConnection]("t4l_solutions")
EMBEDDER = SentenceTransformerEmbedder(sys.argv[3], device="cpu")


@dataclass
class Solution:
    id: str
    repo: str
    feature: str
    summary: str
    embedding: NDArray[np.float32]


@coco.lifespan
async def lifespan(builder: coco.EnvironmentBuilder) -> AsyncIterator[None]:
    builder.provide(STORE, pathlib.Path(sys.argv[1]))
    builder.provide(DB, sqlite.connect(sys.argv[2]))
    yield


@coco.fn(memo=True)
async def embed_run(record: FileLike, table: sqlite.TableTarget[Solution]) -> None:
    rec = json.loads(await record.read_text())
    if not rec.get("summary"):
        return
    repo = record.file_path.path.parent.name
    # e5 models want "passage: " before documents and "query: " before queries.
    prefix = os.environ.get("T4L_SPIKE_DOC_PREFIX", "")
    vec = await EMBEDDER.embed(f"{prefix}{rec['feature']}: {rec['summary']}")
    table.declare_row(row=Solution(
        id=f"{repo}/{rec['run']}", repo=repo, feature=rec["feature"], summary=rec["summary"], embedding=vec,
    ))


@coco.fn
async def app_main() -> None:
    table = await sqlite.mount_table_target(
        DB, "solutions",
        await sqlite.TableSchema.from_class(Solution, primary_key=["id"], column_overrides={"embedding": EMBEDDER}),
    )
    records = localfs.walk_dir(
        STORE, recursive=True, path_matcher=PatternFilePathMatcher(included_patterns=["runs/*/*.json"])
    )
    await coco.mount_each(embed_run, records.items(), table)


app = coco.App(coco.AppConfig(name="t4l_solutions"), app_main)

if __name__ == "__main__":
    app.update_blocking(report_to_stdout=True)
