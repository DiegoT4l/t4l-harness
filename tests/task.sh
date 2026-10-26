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

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
