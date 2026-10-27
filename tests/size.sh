#!/bin/sh
# Tests for scripts/t4l-size.sh and hooks/size-warn.sh. Run: sh tests/size.sh

HERE=$(cd "$(dirname "$0")/.." && pwd)
SIZE="$HERE/scripts/t4l-size.sh"
WARN="$HERE/hooks/size-warn.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0

new_repo() {
	R="$TMP/repo$((PASS + FAIL))"
	mkdir -p "$R"
	git -C "$R" init -q -b main
	git -C "$R" config user.email t@example.com
	git -C "$R" config user.name t
	printf 'one\ntwo\nthree\n' >"$R/a.txt"
	printf 'x\n' >"$R/go.sum"
	git -C "$R" add -A
	git -C "$R" commit -qm base
}

S() { # args...
	OUT=$(cd "$R" && sh "$SIZE" "$@" 2>&1)
	RC=$?
}

check() { # name expected_rc [substring]
	_ok=1
	[ "$RC" -eq "$2" ] || _ok=0
	if [ -n "${3:-}" ]; then
		case $OUT in *"$3"*) ;; *) _ok=0 ;; esac
	fi
	if [ "$_ok" -eq 1 ]; then
		PASS=$((PASS + 1))
		echo "ok   $1"
	else
		FAIL=$((FAIL + 1))
		echo "FAIL $1 (rc=$RC, expected $2, output: $OUT)"
	fi
}

new_repo
S
check "clean tree is 0 lines" 0 "size: 0 lines"

printf 'one\nTWO\nthree\nfour\n' >"$R/a.txt"
S --quiet
check "modified file counts additions plus deletions (+2 -1 = 3)" 0 "3"

printf '1\n2\n3\n4\n5\n' >"$R/new.txt"
S --quiet
check "untracked files count their lines (3 + 5 = 8)" 0 "8"

printf 'changed\n' >"$R/go.sum"
printf '{}\n' >"$R/package-lock.json"
mkdir -p "$R/vendor" "$R/.t4l"
printf 'a\nb\n' >"$R/vendor/x.go"
printf 'a\nb\n' >"$R/.t4l/notes"
S --quiet
check "lockfiles, vendor and .t4l are excluded" 0 "8"

S --budget 5
check "over budget exits 1" 1 "budget 5, 160%"
S --budget 100
check "within budget exits 0" 0 "budget 100, 8%"
S --files --budget 100
check "--files lists the largest files" 0 "new.txt"

printf 'slice_budget=7\n' >/dev/null
mkdir -p "$R/.t4l" && printf 'slice_budget=7\n' >"$R/.t4l/config"
S
check "slice_budget in .t4l/config is the default" 1 "budget 7"

git -C "$R" add -A && git -C "$R" commit -qm change
S --quiet
check "committed changes against HEAD are 0" 0 "0"
S --base HEAD~1 --quiet
check "--base compares with an older ref" 1 "8"
S --base nope
check "unknown base is a setup error" 2 "unknown base"
S --budget abc
check "invalid budget is a usage error" 2

OUT=$(cd "$TMP" && sh "$SIZE" 2>&1)
RC=$?
check "outside a repository is an error" 2 "not inside a git repository"

# --- size-warn hook ----------------------------------------------------------

new_repo
printf 'feature=f\nmode=tdd\ngate=none\nphase=implementing\n' >/dev/null
mkdir -p "$R/.t4l/board"
WT="$R/.claude/worktrees/w1"
git -C "$R" worktree add -q -b wt-w1 "$WT" HEAD
BASE=$(git -C "$R" rev-parse HEAD)
printf 'task=T1\nworktree=%s\nbranch=wt-w1\nbase=%s\nfiles=-\n' "$WT" "$BASE" >"$R/.t4l/board/T1.env"
printf 'slice_budget=10\n' >"$R/.t4l/config"

run_warn() { # file
	OUT=$(printf '{"cwd":"%s","tool_input":{"file_path":"%s"}}' "$WT" "$1" | sh "$WARN" 2>&1)
	RC=$?
}

printf '1\n2\n3\n' >"$WT/n.txt"
run_warn "$WT/n.txt"
check "warn: below 80% is silent" 0
printf '1\n2\n3\n4\n5\n6\n7\n8\n' >"$WT/n.txt"
run_warn "$WT/n.txt"
check "warn: at 80% of the budget it warns once" 2 "8 of 10 lines"
run_warn "$WT/n.txt"
check "warn: it does not repeat for the same task" 0
T4L_HOOKS=off run_warn "$WT/n.txt"
check "warn: T4L_HOOKS=off disables" 0
OUT=$(printf '{"cwd":"%s","tool_input":{"file_path":"%s"}}' "$R" "$R/a.txt" | sh "$WARN" 2>&1)
RC=$?
check "warn: files outside a registered worktree are ignored" 0

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
