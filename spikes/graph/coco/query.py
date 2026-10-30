"""Ask the run history which past runs touched a file, and their verdicts.

    python query.py <path> [host] [port]
"""

import sys

from falkordb import FalkorDB

path = sys.argv[1]
host = sys.argv[2] if len(sys.argv) > 2 else "localhost"
port = int(sys.argv[3]) if len(sys.argv) > 3 else 6390

g = FalkorDB(host=host, port=port).select_graph("t4l_history")
res = g.query(
    "MATCH (r:Run)-[:TOUCHED]->(f:File {path: $path}) "
    "RETURN r.feature, r.id, r.verdict ORDER BY r.id",
    {"path": path},
)
for feature, run, verdict in res.result_set:
    print(f"{feature}\t{run}\t{verdict}")
counts = g.query("MATCH (r:Run) WITH count(r) AS runs MATCH (f:File) RETURN runs, count(f)").result_set
print(f"(graph: {counts[0][0]} runs, {counts[0][1]} files)")
