"""Score the search against the queries in semantic_corpus.json.

    python eval_semantic.py write-store <store>
    python eval_semantic.py vectors <db file> <model>    rank by cosine distance
    python eval_semantic.py keywords <store>              rank by SQLite FTS5 (BM25)

Prints recall@1, recall@3 and MRR, plus the misses.
"""

import json
import os
import pathlib
import sqlite3
import sys
import time

CORPUS = json.loads((pathlib.Path(__file__).parent / "semantic_corpus.json").read_text())


def score(rank) -> None:
    hits1 = hits3 = 0
    rr = 0.0
    misses = []
    t = time.perf_counter()
    for item in CORPUS["queries"]:
        ids = rank(item["q"])
        pos = next((i for i, x in enumerate(ids) if x in item["relevant"]), None)
        if pos is not None:
            rr += 1 / (pos + 1)
            hits1 += pos == 0
            hits3 += pos < 3
        if pos is None or pos >= 3:
            misses.append((item["q"], item["relevant"][0], ids[:3]))
    n = len(CORPUS["queries"])
    ms = (time.perf_counter() - t) * 1000 / n
    print(f"recall@1 {hits1}/{n}  recall@3 {hits3}/{n}  MRR {rr / n:.2f}  ({ms:.0f} ms per query)")
    for q, want, got in misses:
        print(f"  miss: {q!r}\n        want {want}, top 3 {got}")


cmd = sys.argv[1]
if cmd == "write-store":
    root = pathlib.Path(sys.argv[2]) / "runs"
    for r in CORPUS["runs"]:
        d = root / r["repo"]
        d.mkdir(parents=True, exist_ok=True)
        rec = {"run": r["run"], "feature": r["feature"], "verdict": "APPROVED", "attempts": 1,
               "files": [], "summary": r["summary"]}
        (d / f"{r['run']}.json").write_text(json.dumps(rec, ensure_ascii=False) + "\n")
elif cmd == "vectors":
    import sqlite_vec
    from sentence_transformers import SentenceTransformer

    db = sqlite3.connect(sys.argv[2])
    db.enable_load_extension(True)
    sqlite_vec.load(db)
    model = SentenceTransformer(sys.argv[3], device="cpu")

    def rank(q: str) -> list[str]:
        v = model.encode(os.environ.get("T4L_SPIKE_QUERY_PREFIX", "") + q, normalize_embeddings=True).astype("float32").tobytes()
        rows = db.execute(
            "SELECT id FROM solutions ORDER BY vec_distance_cosine(embedding, ?) LIMIT 10", (v,)
        ).fetchall()
        return [r[0] for r in rows]

    score(rank)
elif cmd == "keywords":
    db = sqlite3.connect(":memory:")
    db.execute("CREATE VIRTUAL TABLE s USING fts5(id UNINDEXED, text, tokenize='unicode61 remove_diacritics 2')")
    for r in CORPUS["runs"]:
        db.execute("INSERT INTO s VALUES (?, ?)", (f"{r['repo']}/{r['run']}", f"{r['feature']} {r['summary']}"))

    def rank(q: str) -> list[str]:
        words = [w for w in "".join(c if c.isalnum() else " " for c in q).split() if len(w) > 2]
        match = " OR ".join(f'"{w}"' for w in words)
        return [r[0] for r in db.execute(
            "SELECT id FROM s WHERE s MATCH ? ORDER BY bm25(s) LIMIT 10", (match,)).fetchall()]

    score(rank)
