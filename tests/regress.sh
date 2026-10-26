#!/bin/sh
# Tests for scripts/t4l-regress.sh. Run: sh tests/regress.sh

HERE=$(cd "$(dirname "$0")/.." && pwd)
REGRESS="$HERE/scripts/t4l-regress.sh"

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
	cat >"$R/greet.sh" <<'EOF'
#!/bin/sh
echo "hello $1"
echo "warn" >&2
exit 0
EOF
	git -C "$R" add -A
	git -C "$R" commit -qm base
}

# run_regress <args...>; commands on stdin. Sets OUT and RC.
run_regress() {
	OUT=$(cd "$R" && sh "$REGRESS" "$@" 2>&1)
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
run_regress <<'EOF'
sh greet.sh world
EOF
check "no differences exits 0" 0 "0 differ"

new_repo
sed -i 's/hello/goodbye/' "$R/greet.sh"
run_regress <<'EOF'
sh greet.sh world
EOF
check "changed stdout is reported" 1 "changed: stdout"
case $OUT in *"goodbye world"*) ;; *) FAIL=$((FAIL + 1)); echo "FAIL diff shows the new line" ;; esac

new_repo
sed -i 's/exit 0/exit 3/' "$R/greet.sh"
run_regress <<'EOF'
sh greet.sh world
EOF
check "changed exit code is reported" 1 "exit code: 0 -> 3"

new_repo
sed -i 's/warn/alarm/' "$R/greet.sh"
run_regress <<'EOF'
sh greet.sh world
EOF
check "changed stderr is reported" 1 "changed: stderr"

new_repo
echo new >"$R/new.txt"
run_regress <<'EOF'
test -f new.txt
EOF
check "untracked file counts as a change" 1 "exit code: 1 -> 0"

new_repo
sed -i 's/hello/goodbye/' "$R/greet.sh"
git -C "$R" commit -qam change
run_regress <<'EOF'
sh greet.sh world
EOF
check "committed change vs HEAD is not a difference" 0
run_regress --base HEAD~1 <<'EOF'
sh greet.sh world
EOF
check "--base compares against an older ref" 1 "changed: stdout"

new_repo
run_regress <<'EOF'
# a comment

sh greet.sh world
EOF
check "comments and blank lines are skipped" 0 "1 compared"

new_repo
run_regress <<'EOF'
pwd
EOF
check "repository paths are normalized" 0 "0 differ"

new_repo
printf 'sh greet.sh x\n' >"$TMP/list.txt"
run_regress --file "$TMP/list.txt"
check "--file reads commands from a file" 0 "1 compared"

new_repo
run_regress <<'EOF'
echo /tmp/go-build$$/b001/exe/x
echo /home/u/.cache/go-build/ab/h$$-d/x:
EOF
check "go-build temp paths are normalized" 0 "0 differ"

new_repo
run_regress <<'EOF'
sh greet.sh {edge}
EOF
check "{edge} expands to every built-in edge input" 0 "10 compared"

new_repo
cat >"$R/greet.sh" <<'EOS'
#!/bin/sh
case $1 in -*) echo "unknown flag: $1" >&2; exit 2 ;; esac
echo "hello $1"
exit 0
EOS
git -C "$R" add -A && git -C "$R" commit -qm "flag-aware greet"
cat >"$R/greet.sh" <<'EOS'
#!/bin/sh
echo "hello $1"
exit 0
EOS
run_regress <<'EOF'
sh greet.sh {edge}
EOF
check "{edge} catches option-like text that changed behavior" 1 "4 differ"
case $OUT in *"'--lead'"*) ;; *) FAIL=$((FAIL + 1)); echo "FAIL expanded command is shown quoted" ;; esac

new_repo
run_regress <<'EOF'
printf '[%s]\n' prefix-{edge}-suffix
EOF
check "{edge} keeps the text around the placeholder" 0 "10 compared"

new_repo
run_regress --timeout 1 <<'EOF'
sleep 5
EOF
check "timeout applies on both sides" 0 "0 differ"

new_repo
run_regress </dev/null
check "no commands is a usage error" 2 "no commands"

new_repo
run_regress --base no-such-ref <<'EOF'
true
EOF
check "unknown base ref is a setup error" 2 "cannot check out base ref"

new_repo
run_regress --timeout abc </dev/null
check "invalid timeout is a usage error" 2

OUT=$(cd "$TMP" && sh "$REGRESS" </dev/null 2>&1)
RC=$?
check "outside a git repository is an error" 2 "not inside a git repository"

new_repo
run_regress <<'EOF'
sh greet.sh world
EOF
n=$(git -C "$R" worktree list | wc -l)
if [ "$n" -eq 1 ]; then
	PASS=$((PASS + 1))
	echo "ok   temporary worktree is removed"
else
	FAIL=$((FAIL + 1))
	echo "FAIL temporary worktree left behind ($n entries)"
fi

new_repo
mkdir -p "$R/node_modules/dep"
echo ok >"$R/node_modules/dep/f.txt"
run_regress <<'EOF'
test -f node_modules/dep/f.txt
EOF
check "node_modules is linked into the base checkout" 0 "0 differ"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
