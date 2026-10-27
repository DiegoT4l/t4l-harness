#!/bin/sh
# Tests for scripts/t4l-mutate.sh. Run: sh tests/mutate.sh
# Most cases use a fake gremlins; the last ones use the real one when installed.

HERE=$(cd "$(dirname "$0")/.." && pwd)
MUTATE="$HERE/scripts/t4l-mutate.sh"

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

new_repo() {
	R="$TMP/repo$((PASS + FAIL))"
	mkdir -p "$R"
	git -C "$R" init -q -b main
	git -C "$R" config user.email t@example.com
	git -C "$R" config user.name t
	printf 'module demo\n\ngo 1.22\n' >"$R/go.mod"
	printf 'package demo\n\nfunc Clamp(n int) int {\n\tif n <= 10 {\n\t\treturn n\n\t}\n\treturn 10\n}\n' >"$R/demo.go"
	git -C "$R" add -A
	git -C "$R" commit -qm base
	B=$(git -C "$R" rev-parse HEAD)
}

# fake gremlins: records its arguments and cwd, writes FAKE_JSON to the -o file
FAKE="$TMP/fake-gremlins"
cat >"$FAKE" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$FAKE_LOG/args"
pwd >"$FAKE_LOG/cwd"
ls >"$FAKE_LOG/files"
while [ $# -gt 0 ]; do
	[ "$1" = -o ] && printf '%s' "$FAKE_JSON" >"$2"
	shift
done
EOF
chmod +x "$FAKE"
export FAKE_LOG="$TMP/log"
mkdir -p "$FAKE_LOG"

M() { # args...
	OUT=$(cd "$R" && T4L_GREMLINS="$FAKE" sh "$MUTATE" "$@" 2>&1)
	RC=$?
}

LIVED_JSON='{"files":[{"file_name":"demo.go","mutations":[
{"type":"CONDITIONALS_BOUNDARY","status":"LIVED","line":4,"column":7},
{"type":"CONDITIONALS_NEGATION","status":"KILLED","line":4,"column":7},
{"type":"ARITHMETIC_BASE","status":"SKIPPED","line":9,"column":1}]}]}'
GOOD_JSON='{"files":[{"file_name":"demo.go","mutations":[
{"type":"CONDITIONALS_NEGATION","status":"KILLED","line":4,"column":7},
{"type":"CONDITIONALS_BOUNDARY","status":"TIMED OUT","line":4,"column":7}]}]}'
UNCOVERED_JSON='{"files":[{"file_name":"new.go","mutations":[
{"type":"CONDITIONALS_NEGATION","status":"NOT COVERED","line":3,"column":5}]}]}'

new_repo
M
check "off without config" 0 "mutation: off"

mkdir -p "$R/.t4l"
echo 'mutation=gremlins' >"$R/.t4l/config"
FAKE_JSON=$LIVED_JSON M
check "survivor below threshold fails" 1 "score 50% (threshold 80%)"
check "survivor shows path, line, type and source" 1 "LIVED       demo.go:4  CONDITIONALS_BOUNDARY  | if n <= 10 {"
OUT=$(cat "$FAKE_LOG/args")
RC=0
check "only the diff since the base is mutated" 0 "--diff
$B"

FAKE_JSON=$LIVED_JSON M --threshold 50
check "threshold flag" 0 "score 50% (threshold 50%)"
echo 'mutation_threshold=40' >>"$R/.t4l/config"
FAKE_JSON=$LIVED_JSON M
check "threshold from the config" 0 "threshold 40%"

FAKE_JSON=$GOOD_JSON M
check "timed out counts as killed" 0 "killed 2, lived 0, not covered 0; score 100%"

printf 'package demo\n\nfunc New() int {\n\treturn 1\n}\n' >"$R/new.go"
FAKE_JSON=$UNCOVERED_JSON M
check "not covered counts against the score" 1 "score 0%"
OUT=$(cat "$FAKE_LOG/files")
RC=0
check "untracked files are in the snapshot" 0 "new.go"
OUT=$(cat "$FAKE_LOG/cwd")
case $OUT in "$R"*) RC=1 ;; *) RC=0 ;; esac
check "gremlins runs outside the repository" 0 ""
OUT=$(git -C "$R" status --porcelain; git -C "$R" worktree list | wc -l; git -C "$R" diff --cached --name-only)
RC=0
check "repository untouched: new.go still untracked, no worktree left, empty index" 0 "?? new.go
1"

FAKE_JSON='{"files":[]}' M
check "no mutants in the changed code" 0 "no mutants in the changed code"

FAKE_JSON='' M
check "no result is a setup error" 2 "gremlins produced no result"

M --base nosuchref
check "unknown base is a setup error" 2 "unknown base ref: nosuchref"

new_repo
FAKE_JSON='' M --force
check "--force runs without config" 2 "gremlins produced no result"

new_repo
mkdir -p "$R/.t4l"
echo 'mutation=echo custom-tool-ran; exit 3' >"$R/.t4l/config"
M
check "custom command: its exit status is the verdict" 1 "custom-tool-ran"
echo 'mutation=true' >"$R/.t4l/config"
git -C "$R" add -f .t4l/config
M
check "tracked config: custom command does not run" 2 "is tracked by git"

new_repo
mkdir -p "$R/sub"
mv "$R/go.mod" "$R/sub/go.mod"
git -C "$R" add -A
git -C "$R" commit -qm "module in a subdirectory"
OUT=$(cd "$R" && T4L_GREMLINS="$FAKE" sh "$MUTATE" --force 2>&1)
RC=$?
check "needs to run from the module directory" 2 "no go.mod here"

# real gremlins, when installed: the boundary of n <= 10 is not tested
if command -v gremlins >/dev/null 2>&1 && command -v go >/dev/null 2>&1; then
	new_repo
	printf 'package demo\n\nimport "testing"\n\nfunc TestClamp(t *testing.T) {\n\tif Clamp(3) != 3 || Clamp(50) != 10 {\n\t\tt.Fatal("clamp")\n\t}\n}\n' >"$R/demo_test.go"
	printf 'package demo\n\nfunc Clamp(n int) int {\n\tif n <= 10 {\n\t\treturn n\n\t}\n\treturn 10\n}\n\nfunc Twice(n int) int {\n\treturn n * 2\n}\n' >"$R/demo.go"
	OUT=$(cd "$R" && GOFLAGS=-mod=mod sh "$MUTATE" --force --base "$B" 2>&1)
	RC=$?
	check "real gremlins: untested new function is not covered" 1 "NOT COVERED demo.go:11"
	git -C "$R" add -A
	git -C "$R" commit -qm twice
	printf 'package demo\n\nimport "testing"\n\nfunc TestClamp(t *testing.T) {\n\tif Clamp(3) != 3 || Clamp(50) != 10 {\n\t\tt.Fatal("clamp")\n\t}\n}\n\nfunc TestTwice(t *testing.T) {\n\tif Twice(3) != 6 {\n\t\tt.Fatal("twice")\n\t}\n}\n' >"$R/demo_test.go"
	OUT=$(cd "$R" && sh "$MUTATE" --force --base "$B" 2>&1)
	RC=$?
	check "real gremlins: tested code passes" 0 "lived 0, not covered 0"
else
	echo "skip real gremlins (not installed)"
fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
