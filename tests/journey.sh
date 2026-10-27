#!/bin/sh
# Tests for scripts/t4l-journey.sh and scripts/t4l-checkpoints.sh, with a fake
# claude binary: no tokens are spent. Run: sh tests/journey.sh

HERE=$(cd "$(dirname "$0")/.." && pwd)
JOURNEY="$HERE/scripts/t4l-journey.sh"
CHECKPOINTS="$HERE/scripts/t4l-checkpoints.sh"

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

lacks() { # name substring
	case $OUT in
	*"$2"*)
		FAIL=$((FAIL + 1))
		echo "FAIL $1 (output has '$2': $OUT)"
		;;
	*)
		PASS=$((PASS + 1))
		echo "ok   $1"
		;;
	esac
}

# --- fake claude: logs its arguments and stdin, acts on FAKE_ACTION, prints stream-json
FAKE="$TMP/fake-claude"
cat >"$FAKE" <<'EOF'
#!/bin/sh
prompt=$(cat)
n=$(cat "$FAKE_LOG/count" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" >"$FAKE_LOG/count"
printf '%s\n' "$@" >"$FAKE_LOG/args$n"
printf '%s' "$prompt" >"$FAKE_LOG/prompt$n"
case ${FAKE_ACTION:-} in
readme) echo "planned: --max-len" >>README.md ;;
fail) echo "boom" >&2; exit 1 ;;
seen) [ -f from-setup ] && echo "setup ran" >>README.md ;;
bin) fake-tool >>README.md ;;
esac
echo '{"type":"system","subtype":"init","session_id":"sess-1"}'
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"ODD only: first block"}]}}'
echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"README.md"}}]}}'
echo '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"--- FAIL: TestX"}]}}'
printf '{"type":"result","subtype":"success","is_error":false,"result":"ODD only: reply %s","total_cost_usd":0.25,"num_turns":3,"permission_denials":[]}\n' "$n"
EOF
chmod +x "$FAKE"

FIX="$TMP/fx"
mkdir -p "$FIX"
echo "# demo" >"$FIX/README.md"

J="$TMP/journeys"
mkdir -p "$J"
cat >"$J/good.journey" <<'EOF'
# Passes with the fake.
fixture=../fx
turn 'update the README'

checkpoints() {
	reply_has 'ODD only'
	reply_lacks 'ODD \+ SDD'
	tool_used Read
	tool_unused Agent
	transcript_has '--- FAIL'
	changed README.md
	only_changed README.md
	exists README.md
	absent .t4l/tasks
	cmd 'grep -q planned README.md'
	generic
}
EOF
cat >"$J/bad.journey" <<'EOF'
# Fails one checkpoint.
fixture=../fx
turn 'update the README'

checkpoints() {
	reply_has 'ODD only'
	clean
}
EOF
cat >"$J/multi.journey" <<'EOF'
# Two turns: the second resumes the first session.
fixture=../fx
turn 'write the specs'
turn 'approved, go ahead'
allow='Bash(make test:*)'

checkpoints() {
	reply_has 'reply 2'
}
EOF
cat >"$J/order.journey" <<'EOF'
# Order of events in the transcript.
fixture=../fx
turn 'go'

checkpoints() {
	transcript_order '^Read' 'FAIL: TestX'
	transcript_order 'FAIL: TestX' '^Read'
}
EOF
cat >"$J/history.journey" <<'EOF'
# setup commits on main and adds a fake tool; the session is judged from there.
fixture=../fx
turn 'go'

setup() {
	echo "from setup" >>README.md
	git -c user.email=t@example.com -c user.name=t commit -qam "setup commit"
	printf '#!/bin/sh\necho fake tool ran\n' >"$BIN/fake-tool"
	chmod +x "$BIN/fake-tool"
}

checkpoints() {
	only_changed README.md
	cmd 'grep -q "fake tool ran" README.md'
	cmd '[ "$(git diff HEAD | grep -c "^+[^+]")" -eq 1 ]'
	generic
}
EOF
cat >"$J/setup.journey" <<'EOF'
# setup() runs in the work copy before the session.
fixture=../fx
turn 'go'

setup() {
	touch from-setup
}

checkpoints() {
	cmd 'grep -q "setup ran" README.md'
}
EOF

run() { # out-dir args...
	_o=$1
	shift
	rm -rf "$FAKE_LOG"
	mkdir -p "$FAKE_LOG"
	OUT=$(T4L_CLAUDE="$FAKE" sh "$JOURNEY" --out "$TMP/$_o" "$@" 2>&1)
	RC=$?
}
export FAKE_LOG="$TMP/log"

OUT=$(sh "$JOURNEY" --list 2>&1)
RC=$?
check "list shows the shipped journeys" 0 "bug-tdd"

FAKE_ACTION=readme run r-good "$J/good.journey"
check "passing journey exits 0" 0 "good"
OUT=$(cat "$TMP/r-good/summary.tsv")
check "summary.tsv records pass" 0 "good	1	pass"
check "cost is read from the result event" 0 "0.25"
OUT=$(cat "$TMP/r-good/good/run1/replies.txt")
check "replies include earlier text blocks" 0 "ODD only: first block"
OUT=$(grep '^FAIL' "$TMP/r-good/good/run1/checkpoints.txt")
lacks "no failed checkpoint" "FAIL"
OUT=$(cat "$TMP/r-good/good/run1/checkpoints.txt")
check "generic checkpoints are included" 0 "ok   generic: attribution"

FAKE_ACTION=readme run r-bad "$J/bad.journey"
check "failing checkpoint exits 1" 1 "FAIL clean (changed: README.md"

run r-multi "$J/multi.journey"
check "multi-turn journey passes" 0 "pass"
OUT=$(cat "$FAKE_LOG/prompt2")
check "second prompt arrives on stdin" 0 "approved, go ahead"
OUT=$(cat "$FAKE_LOG/args2")
check "second turn resumes the session" 0 "--resume
sess-1"
OUT=$(cat "$FAKE_LOG/args1")
lacks "first turn does not resume" "--resume"
check "allowed rule with spaces is one argument" 0 "
Bash(sh $HERE/scripts/*)
"
check "journey allow is appended" 0 "Bash(make test:*)"
check "Engram is disabled by default" 0 '"engram@engram":false'

FAKE_ACTION=fail run r-fail "$J/good.journey"
check "session error fails the run" 1 "FAIL session turn 1"

FAKE_ACTION=seen run r-setup "$J/setup.journey"
check "setup runs before the session" 0 "pass"

FAKE_ACTION=readme run r-rep --repeat 2 "$J/good.journey"
OUT=$(cat "$TMP/r-rep/summary.tsv")
check "repeat runs the journey twice" 0 "good	2	pass"

OUT=$(sh "$JOURNEY" --compare "$TMP/r-good" "$TMP/r-rep" 2>&1)
RC=$?
check "compare shows pass rates" 0 "1/1     2/2"

run r-order "$J/order.journey"
OUT=$(cat "$TMP/r-order/order/run1/checkpoints.txt")
check "transcript_order holds in order" 1 "ok   transcript_order ^Read before FAIL: TestX"
check "transcript_order fails reversed" 1 "FAIL transcript_order FAIL: TestX before ^Read"

FAKE_ACTION=bin run r-hist "$J/history.journey"
check "fake tools from setup are on the session PATH; base is the state after setup" 0 "pass"
OUT=$(cat "$TMP/r-hist/history/run1/checkpoints.txt")
check "a setup commit on main does not move the protected branch" 0 "ok   generic: protected"

OUT=$(sh "$JOURNEY" --out "$TMP/x" nope 2>&1)
RC=$?
check "unknown journey is a usage error" 2 "no such journey"

# --- t4l-checkpoints.sh

new_repo() {
	R="$TMP/repo$((PASS + FAIL))"
	mkdir -p "$R"
	git -C "$R" init -q -b main
	git -C "$R" config user.email t@example.com
	git -C "$R" config user.name t
	echo base >"$R/base.txt"
	git -C "$R" add -A
	git -C "$R" commit -qm base
	B=$(git -C "$R" rev-parse HEAD)
}
C() {
	OUT=$(cd "$R" && sh "$CHECKPOINTS" "$@" 2>&1)
	RC=$?
}

new_repo
C
check "no base: commit checks skipped" 0 "skip attribution"

C --base "$B"
check "untouched repo passes" 0 "ok   protected"

git -C "$R" checkout -qb feat
echo x >>"$R/base.txt"
git -C "$R" commit -qam "feat: x"
C --base "$B"
check "plain commit on a feature branch passes" 0 "ok   attribution"

new_repo
echo x >>"$R/base.txt"
git -C "$R" commit -qam "change on main"
C --base "$B"
check "protected branch moved fails" 1 "FAIL protected: moved since the base: main"

new_repo
mkdir -p "$R/.t4l"
echo 'protected_branches=release' >"$R/.t4l/config"
echo x >>"$R/base.txt"
git -C "$R" commit -qam "change on main"
C --base "$B"
check "protected_branches from the config" 0 "ok   protected"

new_repo
git -C "$R" for-each-ref --format='%(objectname) %(refname)' refs/heads >"$TMP/refs"
git -C "$R" checkout -qb feat
echo y >>"$R/base.txt"
git -C "$R" commit -qam "feat: y"
C --refs "$TMP/refs"
check "refs: a new branch does not move main" 0 "ok   protected"
git -C "$R" checkout -q main
git -C "$R" merge -q --ff-only feat
C --refs "$TMP/refs"
check "refs: main moved fails" 1 "FAIL protected: moved since the base: main"
C --refs "$TMP/refs" --base HEAD
check "refs and base together are a usage error" 2 "not both"

new_repo
C --verify 'false'
check "failing verify fails" 1 "FAIL verify"
C --verify 'true'
check "passing verify passes" 0 "ok   verify"

mkdir -p "$R/.t4l"
echo 'verify=false' >"$R/.t4l/config"
C
check "verify from the config" 1 "FAIL verify: false"
git -C "$R" add -f .t4l/config
C
check "tracked config does not run" 0 "skip verify: .t4l/config is tracked"

new_repo
(cd "$R" && sh "$HERE/scripts/t4l-task.sh" new demo --mode tdd --request "do it" >/dev/null 2>&1)
C
check "coherent feature passes" 0 "ok   feature"
sed -i 's/^phase=.*/phase=done/' "$R/.t4l/state"
C
check "closed feature without judge report fails" 1 "without .t4l/reports/judge_demo.md"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
