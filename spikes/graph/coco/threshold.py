"""Can a distance cutoff tell "already solved elsewhere" from "nothing similar"?

Prints the cosine distance of the best hit for the queries that have an
answer in the corpus and for queries that have none.

    python threshold.py <db file> <model>
"""

import json
import pathlib
import sqlite3
import sys

import sqlite_vec
from sentence_transformers import SentenceTransformer

NONE = [
    "añadir soporte para subir fotos de perfil y recortarlas",
    "translate the admin panel into German and French",
    "calcular el envío según el peso y el código postal",
    "add a GraphQL endpoint for the product catalog",
    "generar un QR para cada ticket de un evento",
    "play a sound when a chat message arrives",
    "exportar el calendario de turnos a Google Calendar",
    "train a model to classify support tickets by topic",
]

corpus = json.loads((pathlib.Path(__file__).parent / "semantic_corpus.json").read_text())
db = sqlite3.connect(sys.argv[1])
db.enable_load_extension(True)
sqlite_vec.load(db)
model = SentenceTransformer(sys.argv[2], device="cpu")


def best(q: str) -> tuple[str, float]:
    v = model.encode(q, normalize_embeddings=True).astype("float32").tobytes()
    return db.execute(
        "SELECT id, vec_distance_cosine(embedding, ?) d FROM solutions ORDER BY d LIMIT 1", (v,)
    ).fetchone()


pos = [(item["q"], *best(item["q"]), item["relevant"][0]) for item in corpus["queries"]]
neg = [(q, *best(q)) for q in NONE]
for q, hit, d, want in sorted(pos, key=lambda x: x[2]):
    print(f"answer  {d:.3f}  {'ok ' if hit == want else 'BAD'} {hit:28s} {q[:60]}")
for q, hit, d in sorted(neg, key=lambda x: x[2]):
    print(f"none    {d:.3f}      {hit:28s} {q[:60]}")
worst_pos = max(d for _, _, d, _ in pos)
best_neg = min(d for _, _, d in neg)
print(f"largest distance with an answer {worst_pos:.3f}, smallest with none {best_neg:.3f}")
