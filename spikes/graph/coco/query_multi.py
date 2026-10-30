"""The same cross-repository questions against both backends.

    python query_multi.py falkor <path> [host] [port]
    python query_multi.py sqlite <path> <db file>
"""

import sqlite3
import sys
import time

backend, path = sys.argv[1], sys.argv[2]

CYPHER = {
    "who touched this path, in any repo": (
        "MATCH (r:Run)-[:TOUCHED]->(f:File {path: $path}) "
        "RETURN r.repo, r.feature, r.verdict ORDER BY r.repo, r.id"
    ),
    "paths touched in more than one repo": (
        "MATCH (r:Run)-[:TOUCHED]->(f:File) WITH f.path AS path, collect(DISTINCT r.repo) AS repos "
        "WHERE size(repos) > 1 RETURN path, repos ORDER BY path"
    ),
    "rejection rate and attempts per repo": (
        "MATCH (r:Run)-[:IN]->(p:Repo) "
        "RETURN p.name, count(r), sum(CASE WHEN r.verdict = 'CHANGES_REQUESTED' THEN 1 ELSE 0 END), avg(r.attempts) "
        "ORDER BY p.name"
    ),
    "paths rejected in one repo and touched in another": (
        "MATCH (bad:Run {verdict: 'CHANGES_REQUESTED'})-[:TOUCHED]->(f:File) "
        "WITH DISTINCT f.path AS path, f.repo AS repo "
        "MATCH (g:File {path: path}) WHERE g.repo <> repo "
        "RETURN path, repo, g.repo ORDER BY path, repo, g.repo"
    ),
}

SQL = {
    "who touched this path, in any repo": (
        "SELECT r.repo, r.feature, r.verdict FROM touched t JOIN runs r ON r.id = t.run "
        "WHERE t.path = ? ORDER BY r.repo, r.id"
    ),
    "paths touched in more than one repo": (
        "SELECT path, group_concat(DISTINCT repo) FROM touched GROUP BY path "
        "HAVING count(DISTINCT repo) > 1 ORDER BY path"
    ),
    "rejection rate and attempts per repo": (
        "SELECT repo, count(*), sum(verdict = 'CHANGES_REQUESTED'), avg(attempts) FROM runs "
        "GROUP BY repo ORDER BY repo"
    ),
    "paths rejected in one repo and touched in another": (
        "WITH bad AS (SELECT DISTINCT t.path, t.repo FROM touched t JOIN runs r ON r.id = t.run "
        "WHERE r.verdict = 'CHANGES_REQUESTED'), seen AS (SELECT DISTINCT path, repo FROM touched) "
        "SELECT b.path, b.repo, s.repo FROM bad b JOIN seen s ON s.path = b.path AND s.repo <> b.repo "
        "ORDER BY b.path, b.repo, s.repo"
    ),
}

if backend == "falkor":
    from falkordb import FalkorDB

    host = sys.argv[3] if len(sys.argv) > 3 else "localhost"
    port = int(sys.argv[4]) if len(sys.argv) > 4 else 6390
    g = FalkorDB(host=host, port=port).select_graph("t4l_history")

    def ask(name: str) -> list:
        return g.query(CYPHER[name], {"path": path}).result_set
else:
    db = sqlite3.connect(sys.argv[3])

    def ask(name: str) -> list:
        args = (path,) if "?" in SQL[name] else ()
        return db.execute(SQL[name], args).fetchall()

for name in CYPHER:
    t = time.perf_counter()
    rows = ask(name)
    ms = (time.perf_counter() - t) * 1000
    print(f"## {name} ({ms:.1f} ms)")
    for row in rows:
        print("  " + " | ".join(str(c) for c in row))
