"""Write a run store for the cross-repository spike.

    python make_store.py <store> sample            three repos with shared paths
    python make_store.py <store> scale <repos> <runs per repo>
"""

import json
import pathlib
import random
import sys

store = pathlib.Path(sys.argv[1]) / "runs"

SAMPLE = {
    "t4l-harness": [
        ("bash-guard", "CHANGES_REQUESTED", 1, ["hooks/guard.sh", "hooks/bash-guard.sh", ".github/workflows/ci.yml"]),
        ("bash-guard", "APPROVED", 2, ["hooks/guard.sh", "hooks/bash-guard.sh", "tests/hooks.sh"]),
    ],
    "termix-skills": [
        ("fleet-ops", "APPROVED", 1, ["skills/fleet/SKILL.md", ".github/workflows/ci.yml"]),
        ("tunnel", "CHANGES_REQUESTED", 3, ["go.mod", "cmd/tunnel.go"]),
    ],
    "t4l-sandbox": [
        ("fix-parse", "APPROVED", 1, ["go.mod", "main.go", "hooks/guard.sh"]),
    ],
}


def write(repo: str, n: int, feature: str, verdict: str, attempts: int, files: list[str]) -> None:
    d = store / repo
    d.mkdir(parents=True, exist_ok=True)
    rec = {"run": f"{n:05d}", "feature": feature, "verdict": verdict, "attempts": attempts, "files": files}
    (d / f"{n:05d}.json").write_text(json.dumps(rec) + "\n")


if sys.argv[2] == "sample":
    for repo, runs in SAMPLE.items():
        for i, run in enumerate(runs, 1):
            write(repo, i, *run)
else:
    repos, per = int(sys.argv[3]), int(sys.argv[4])
    rnd = random.Random(38)
    shared = ["go.mod", "go.sum", ".github/workflows/ci.yml", "Makefile", "README.md"]
    for r in range(repos):
        own = [f"pkg/r{r}m{m}/f{f}.go" for m in range(20) for f in range(10)]
        for n in range(1, per + 1):
            files = rnd.sample(own, rnd.randint(1, 6)) + rnd.sample(shared, rnd.randint(0, 2))
            verdict = "CHANGES_REQUESTED" if rnd.random() < 0.3 else "APPROVED"
            write(f"repo{r:02d}", n, f"feat{n}", verdict, rnd.randint(1, 3), files)
