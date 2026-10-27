#!/bin/sh
# Tests for scripts/t4l-integrate.sh. Run: sh tests/integrate.sh

HERE=$(cd "$(dirname "$0")/.." && pwd)
TASK="$HERE/scripts/t4l-task.sh"
INTEGRATE="$HERE/scripts/t4l-integrate.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0

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

assert() { # name command...
	_name=$1
	shift
	if "$@"; then
		PASS=$((PASS + 1))
		echo "ok   $_name"
	else
		FAIL=$((FAIL + 1))
		echo "FAIL $_name"
	fi
}

new_repo() {
	R="$TMP/repo$((PASS + FAIL))"
	mkdir -p "$R"
	git -C "$R" init -q -b main
	git -C "$R" config user.email t@example.com
	git -C "$R" config user.name t
	printf 'l1\nl2\nl3\n' >"$R/s.txt"
	git -C "$R" add -A
	git -C "$R" commit -qm base
}

# tk <dir> <args...>: run t4l-task.sh from a directory.
tk() {
	_d=$1
	shift
	(cd "$_d" && sh "$TASK" "$@" >/dev/null 2>&1)
}

# integ <args...>: run the integrate script from the main checkout. Sets OUT, RC.
integ() {
	OUT=$(cd "$R" && sh "$INTEGRATE" "$@" 2>&1)
	RC=$?
}

# setup: feature f with T1 (a/**) and T2 (b/**), worktrees w1 and w2, both started.
setup() {
	new_repo
	tk "$R" new f --mode tdd --request r
	tk "$R" add T1 S1 --files 'a/**'
	tk "$R" add T2 S1 --files 'b/**'
	tk "$R" parallel on
	W1="$R/.claude/worktrees/w1"
	W2="$R/.claude/worktrees/w2"
	git -C "$R" worktree add -q -b wt-w1 "$W1" HEAD
	git -C "$R" worktree add -q -b wt-w2 "$W2" HEAD
	tk "$W1" start T1
	tk "$W2" start T2
}

work() { # makes a/x.txt (uncommitted) in w1 and b/y.txt (committed) in w2
	mkdir -p "$W1/a" "$W2/b"
	printf 'x1\nx2\n' >"$W1/a/x.txt"
	printf 'y1\ny2\n' >"$W2/b/y.txt"
	git -C "$W2" add -A && git -C "$W2" commit -qm "T2 work"
	tk "$W1" review T1
	tk "$W2" review T2
}

setup
work
integ --verify 'test -f a/x.txt && test -f b/y.txt'
check "integrates both tasks and verifies on the merged tree" 0 "integrated: T1 T2"
assert "the integration branch holds both tasks' files" test -f "$R/.t4l/worktrees/integration/a/x.txt" -a -f "$R/.t4l/worktrees/integration/b/y.txt"
assert "uncommitted work was snapshotted on the task branch" sh -c "git -C '$R' log wt-w1 --format=%s | grep -q 'wip(T1)'"
assert "main was not touched" test "$(git -C "$R" rev-parse main)" = "$(git -C "$R" rev-parse HEAD)"
assert "main has no merge commits" sh -c "[ \$(git -C '$R' log main --oneline | wc -l) -eq 1 ]"
assert "the report is written" test -f "$R/.t4l/reports/integrate_f.md"
case $OUT in *"slice 1: T1, T2"*) PASS=$((PASS + 1)); echo "ok   both tasks fit in one slice" ;; *) FAIL=$((FAIL + 1)); echo "FAIL slice proposal: $OUT" ;; esac

integ --verify 'test -f a/x.txt && test -f b/y.txt'
check "running it again is idempotent" 0 "integrated: T1 T2"

setup
work
integ --verify 'false'
check "a failing verify exits 1 and says so" 1 "verify: exit 1"
assert "the report records the failing verification" grep -q 'exit 1' "$R/.t4l/reports/integrate_f.md"

setup
work
printf 'true\n' >"$TMP/same.cmds"
integ --regress-file "$TMP/same.cmds"
check "a regression file with no differences passes" 0 "regress: exit 0"
printf 'test -f a/x.txt\n' >"$TMP/diff.cmds"
integ --regress-file "$TMP/diff.cmds"
check "a regression difference on the merged tree exits 1" 1 "regress: exit 1"

setup
work
printf 'slice_budget=3\n' >"$R/.t4l/config"
integ
check "a small budget splits the work into slices" 0 "slice 2: T2"

# --- order by dependencies -------------------------------------------------------
new_repo
tk "$R" new f --mode tdd --request r
tk "$R" add T1 S1 --files 'a/**' --deps T2
tk "$R" add T2 S1 --files 'b/**'
tk "$R" parallel on
W1="$R/.claude/worktrees/w1"
W2="$R/.claude/worktrees/w2"
git -C "$R" worktree add -q -b wt-w1 "$W1" HEAD
git -C "$R" worktree add -q -b wt-w2 "$W2" HEAD
tk "$W2" start T2
tk "$W1" review T2 2>/dev/null
tk "$W2" review T2
tk "$W1" start T1
work
integ
check "dependencies decide the merge order (T2 before T1)" 0 "integrated: T2 T1"

# --- sizes of a dependent task exclude what it merged first ---------------------------
new_repo
tk "$R" new f --mode tdd --request r
tk "$R" add T1 S1 --files 'a/**'
tk "$R" add T2 S1 --files 'b/**' --deps T1
tk "$R" parallel on
W1="$R/.claude/worktrees/w1"
W2="$R/.claude/worktrees/w2"
git -C "$R" worktree add -q -b wt-w1 "$W1" HEAD
git -C "$R" worktree add -q -b wt-w2 "$W2" HEAD
tk "$W1" start T1
mkdir -p "$W1/a" && printf '1\n2\n' >"$W1/a/x.txt"
git -C "$W1" add -A && git -C "$W1" commit -qm "T1"
tk "$W1" review T1
git -C "$W2" merge -q --no-edit wt-w1
tk "$W2" start T2
mkdir -p "$W2/b" && printf '1\n2\n' >"$W2/b/y.txt"
tk "$W2" review T2
integ
check "a dependent task integrates" 0 "integrated: T1 T2"
assert "the dependent task's size excludes the work it merged first" grep -q -- '- T2: 2 lines' "$R/.t4l/reports/integrate_f.md"
assert "the integrated total is not double counted" grep -q 'Integrated total: 4 lines' "$R/.t4l/reports/integrate_f.md"

# --- a relative regress file is resolved from the caller's directory ------------------------
setup
work
printf 'true\n' >"$R/rel.cmds"
integ --regress-file rel.cmds
check "a relative --regress-file is read from the caller's directory" 0 "regress: exit 0"

# --- conflict and continue ------------------------------------------------------------
setup
mkdir -p "$W1/a" "$W2/b"
printf 'ONE\nl2\nl3\n' >"$W1/s.txt"
printf 'TWO\nl2\nl3\n' >"$W2/s.txt"
echo a >"$W1/a/f"
echo b >"$W2/b/f"
tk "$W1" review T1
tk "$W2" review T2
integ
check "a merge conflict exits 3 and lists the files" 3 "s.txt"
case $OUT in *"merging T2"*) PASS=$((PASS + 1)); echo "ok   the conflict names the task" ;; *) FAIL=$((FAIL + 1)); echo "FAIL conflict does not name the task: $OUT" ;; esac
printf 'BOTH\nl2\nl3\n' >"$R/.t4l/worktrees/integration/s.txt"
git -C "$R/.t4l/worktrees/integration" add s.txt
git -C "$R/.t4l/worktrees/integration" commit -q --no-edit
integ
check "after resolving, running again completes" 0 "integrated: T1 T2"
assert "the resolution is kept" grep -q BOTH "$R/.t4l/worktrees/integration/s.txt"

# --- refusals ----------------------------------------------------------------------------
setup
mkdir -p "$W1/a" && echo x >"$W1/a/f"
tk "$W1" review T1
integ
check "a task still doing blocks the integration" 2 "must be in review or done"

new_repo
tk "$R" new f --mode tdd --request r
tk "$R" add T1 S1
tk "$R" start T1
tk "$R" review T1
integ
check "a task started in the main checkout cannot be integrated" 2 "main checkout"

new_repo
tk "$R" new f --mode tdd --request r
integ
check "no started task is an error" 2 "nothing to integrate"

setup
work
integ
integ --abort
check "--abort removes the integration" 0 "integration removed"
assert "--abort deletes the worktree" test ! -d "$R/.t4l/worktrees/integration"
assert "--abort deletes the branch" sh -c "! git -C '$R' rev-parse --verify -q t4l/f/integration"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
