#!/bin/sh
# Tests for scripts/t4l-task.sh. Run: sh tests/task.sh

HERE=$(cd "$(dirname "$0")/.." && pwd)
TASK="$HERE/scripts/t4l-task.sh"

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
	echo base >"$R/base.txt"
	git -C "$R" add -A
	git -C "$R" commit -qm base
}

# T <args...>: run the script in the repo. Sets OUT and RC.
T() {
	OUT=$(cd "$R" && sh "$TASK" "$@" 2>&1)
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

assert() { # name command...  (passes when the command succeeds)
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

doc() { echo "$R/.t4l/tasks/$1.md"; }
has() { grep -q "$1" "$2"; }

fill_specs() { # feature
	sed -i 's/^S1\. <behavior>.*/S1. Truncate the slug to N characters./' "$(doc "$1")"
	sed -i 's/^    Existing behavior at risk:.*/    Existing behavior at risk: none, the flag is new./' "$(doc "$1")"
	sed -i 's/^L1\. <the user request, verbatim>/L1. add a --max-len flag/' "$(doc "$1")"
}

# --- new -------------------------------------------------------------------

new_repo
T new max-len --request "add a --max-len flag"
check "new: creates document and state (sdd default)" 0 "gate=pending"
assert "new: state has gate=pending" has '^gate=pending' "$R/.t4l/state"
assert "new: state has phase=specs" has '^phase=specs' "$R/.t4l/state"
assert "new: L1 holds the request verbatim" has 'L1. add a --max-len flag' "$(doc max-len)"
assert "new: adds .t4l/ to .gitignore" grep -qx '\.t4l/' "$R/.gitignore"

T new other
check "new: refuses while a feature is active" 1 "still active"

new_repo
T new "Bad Name"
check "new: rejects invalid feature names" 1 "lowercase"

new_repo
T new f --mode xyz
check "new: rejects unknown mode" 1 "mode must be"

new_repo
T new f --mode tdd
check "new: tdd mode starts at phase=implementing without a gate" 0 "phase=implementing"

# --- approve ---------------------------------------------------------------

new_repo
T new f --request "r"
T approve
check "approve: refuses the template placeholder" 1 "placeholder"
fill_specs f
sed -i '/Existing behavior at risk/d' "$(doc f)"
T approve
check "approve: refuses specs without 'Existing behavior at risk'" 1 "Existing behavior at risk"

new_repo
T new f --request "r"
fill_specs f
T approve
check "approve: ok once specs are filled" 0 "phase=implementing"
T approve
check "approve: nothing to approve twice" 1 "nothing to approve"

new_repo
T new f --mode tdd
T approve
check "approve: not applicable without a gate" 1 "nothing to approve"

# --- add / start / review / done ------------------------------------------

new_repo
T new f --request "r"
fill_specs f
T add T1 S1
check "add: allowed before approval (planning)" 0 "added T1"
T start T1
check "start: refused before approval" 1 "not approved"
T approve
T start T1
check "start: ok after approval" 0 "T1: doing"

T add T1 S1
check "add: duplicate task refused" 1 "already exists"
T add X1 S1
check "add: invalid id refused" 1 "must look like"
T add T2 S9
check "add: unknown spec refused" 1 "not in the document"

T add T2 S1 --deps T1 --files 'cmd/**,internal/slug/**'
check "add: deps and files accepted" 0 "added T2"
T add T3 S1
T start T3
check "start: WIP limit 1 refuses a second task" 1 "WIP limit"

T start T2
check "start: refuses while a dependency is still doing" 1 "depends on T1"

T review T1
check "review: doing -> review" 0 "T1: review"
T start T2
check "start: a dependency in review is enough" 0 "T2: doing"

T "done" T1 deadbeef
check "done: unknown commit refused" 1 "not found"
SHA=$(git -C "$R" rev-parse HEAD)
T "done" T1 "$SHA"
check "done: records the short commit" 0 "T1: done ($(echo "$SHA" | cut -c1-7))"
T status
check "status: lists tasks with files" 0 "files=cmd/**,internal/slug/**"

T "done" T2
check "done: sha is optional" 0 "T2: done (-)"

# --- reopen / log ----------------------------------------------------------

T reopen T2 "spec changed"
check "reopen: back to todo" 0 "T2: todo"
assert "reopen: reason is logged" has 'reopened T2: spec changed' "$(doc f)"
T log "decision: hard cut"
check "log: appends a numbered line" 0
assert "log: line present" has '^L[0-9]*\. decision: hard cut' "$(doc f)"

# --- check -----------------------------------------------------------------

new_repo
T new f --request "r"
fill_specs f
T approve
T add T1 S1
T check
check "check: clean document" 0 "check: ok"

sed -i 's/| T1 | S1 |/| T1 | S7 |/' "$(doc f)"
T check
check "check: detects a task pointing to a missing spec" 1 "missing spec S7"
sed -i 's/| T1 | S7 |/| T1 | S1 |/' "$(doc f)"

T add T2 S1
sed -i 's/| T1 | S1 | todo/| T1 | S1 | doing/; s/| T2 | S1 | todo/| T2 | S1 | doing/' "$(doc f)"
T check
check "check: detects WIP over the limit" 1 "WIP limit is 1"
printf 'wip=2\n' >"$R/.t4l/config"
T check
check "check: wip=2 in config allows two doing" 0 "check: ok"

sed -i 's/| T2 | S1 | doing | - | - | - |/| T2 | S1 | done | - | - | abc1234 |/' "$(doc f)"
T check
check "check: detects a done task with a commit that does not exist" 1 "does not exist"

new_repo
T new f --request "r"
fill_specs f
printf 'gate=pending\nfeature=f\nmode=sdd\nphase=implementing\n' >"$R/.t4l/state"
T check
check "check: sdd implementing without approval is a problem" 1 "not approved"

# --- close -----------------------------------------------------------------

new_repo
T new f --request "r"
fill_specs f
T approve
T add T1 S1
T close
check "close: refused while a task is not done" 1 "T1 is not done"
T start T1
T "done" T1
T close
check "close: ok when all tasks are done" 0 "phase=done"
T new g --mode tdd
check "new: a new feature is allowed after close" 0 "created"

new_repo
T status
check "status: no active feature" 0 "no active feature"
T start T1
check "start: no active feature" 1 "no active feature"

# --- parallel mode, board, overlap ------------------------------------------

# TW <worktree> <args...>: run the script from inside a linked worktree.
TW() {
	_w=$1
	shift
	OUT=$(cd "$_w" && sh "$TASK" "$@" 2>&1)
	RC=$?
}

new_wt() { # name -> $WT
	WT="$R/.claude/worktrees/$1"
	git -C "$R" worktree add -q -b "wt-$1" "$WT" HEAD
}

new_repo
T new f --mode tdd --request "r"
T add T1 S1 --files 'cmd/**'
T add T2 S1 --files 'cmd/x/**'
T add T3 S1 --files 'internal/**'
T add T4 S1 --files 'cmdline/**'
T add T5 S1
T plan-check
check "plan-check: reports overlapping Files and undeclared Files" 1 "T1 and T2 may overlap"
case $OUT in *"T5 has no Files"*) ;; *) FAIL=$((FAIL + 1)); echo "FAIL plan-check: undeclared Files not reported" ;; esac
case $OUT in *"T1 and T4"*) FAIL=$((FAIL + 1)); echo "FAIL plan-check: cmd/** and cmdline/** do not overlap" ;; *) PASS=$((PASS + 1)); echo "ok   plan-check: cmd/** and cmdline/** do not overlap" ;; esac
case $OUT in *"T1 and T3"*) FAIL=$((FAIL + 1)); echo "FAIL plan-check: cmd/** and internal/** do not overlap" ;; *) PASS=$((PASS + 1)); echo "ok   plan-check: cmd/** and internal/** do not overlap" ;; esac

mkdir -p "$R/cmd/slug" && echo x >"$R/cmd/slug/main.go"
(cd "$R" && sh "$TASK" plan-check >"$TMP/pc.out" 2>&1)
assert "plan-check: overlap is detected even when the globbed directories exist" grep -q "T1 and T2 may overlap" "$TMP/pc.out"
rm -rf "$R/cmd"

T parallel on
check "parallel on: WIP limit 2" 0 "limit 2"
assert "parallel on: ignores .claude/worktrees/ locally (.git/info/exclude)" grep -qx '\.claude/worktrees/' "$R/.git/info/exclude"
assert "parallel on: does not touch the tracked .gitignore" sh -c "! grep -q 'claude/worktrees' '$R/.gitignore'"
assert "parallel on: state records it" has '^parallel=1' "$R/.t4l/state"

T start T1
check "start: parallel mode refuses the main checkout" 1 "isolated worktree"
new_wt a
TW "$WT" start T5
check "start: parallel mode refuses undeclared Files" 1 "declare Files"
TW "$WT" start T1
check "start: parallel mode accepts a worktree with declared Files" 0 "T1: doing"
assert "start: registry records the worktree" has "^worktree=$WT" "$R/.t4l/board/T1.env"
assert "start: registry records the branch" has '^branch=wt-a' "$R/.t4l/board/T1.env"
assert "start: registry records the files" has '^files=cmd/\*\*' "$R/.t4l/board/T1.env"

new_wt b
TW "$WT" start T2
check "start: refuses a task whose Files overlap a doing task" 1 "overlaps with T1"
TW "$WT" start T3
check "start: a disjoint task fits in the second WIP slot" 0 "T3: doing"
new_wt c
TW "$WT" start T4
check "start: the third task hits the WIP limit" 1 "WIP limit"

T board
check "board: shows WIP and owners" 0 "WIP 2/2"
case $OUT in *"T1[wt-a]"*) ;; *) FAIL=$((FAIL + 1)); echo "FAIL board: owner branch not shown" ;; esac

TW "$R/.claude/worktrees/a" status
check "status: works from inside a worktree (state lives in the main root)" 0 "feature=f"

T review T1
T reopen T1 "scope changed"
assert "reopen: removes the registry entry" test ! -f "$R/.t4l/board/T1.env"

TW "$R/.claude/worktrees/a" where
check "where: prints the main checkout's reports dir, even from a worktree" 0 "reports=$R/.t4l/reports"

T parallel off
check "parallel off: back to WIP 1" 0 "limit 1"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
