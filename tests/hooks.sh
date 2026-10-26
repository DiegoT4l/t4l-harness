#!/bin/sh
# Tests for t4l hooks and t4l-init. Run: sh tests/hooks.sh
# Uses throwaway git repos; never touches the real home or any real repo.

HERE=$(cd "$(dirname "$0")/.." && pwd)
POST="$HERE/hooks/post-edit-check.sh"
STOP="$HERE/hooks/stop-verify.sh"
INIT="$HERE/scripts/t4l-init.sh"

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
	mkdir -p "$R/.t4l" "$R/sub"
}

write_cfg() {
	printf '%s\n' "$@" >"$R/.t4l/config"
}

# run_post <relative file>
run_post() {
	OUT=$(printf '{"cwd":"%s","tool_input":{"file_path":"%s"}}' "$R" "$1" | sh "$POST" 2>&1)
	RC=$?
}

# run_stop [extra json fields]
run_stop() {
	OUT=$(printf '{"cwd":"%s"%s}' "$R" "${1:-}" | sh "$STOP" 2>&1)
	RC=$?
}

check() { # name expected_rc [expected substring]
	_ok=1
	[ "$RC" -eq "$2" ] || _ok=0
	if [ -n "${3:-}" ]; then
		case $OUT in *"$3"*) ;; *) _ok=0 ;; esac
	fi
	if [ "$2" -eq 0 ] && [ -z "${3:-}" ] && [ -n "$OUT" ]; then _ok=0; fi
	if [ "$_ok" -eq 1 ]; then
		PASS=$((PASS + 1))
		echo "ok   $1"
	else
		FAIL=$((FAIL + 1))
		echo "FAIL $1 (rc=$RC, expected $2, output: $OUT)"
	fi
}

# --- post-edit-check -------------------------------------------------------

new_repo
run_post "a.go"
check "post: no config is a silent no-op" 0

new_repo
write_cfg "quick=false" "quick_ext=go"
run_post "a.go"
check "post: failing quick check exits 2 with message" 2 "t4l quick check failed"

new_repo
write_cfg "quick=true" "quick_ext=go"
run_post "a.go"
check "post: passing quick check is silent" 0

new_repo
write_cfg "quick=false" "quick_ext=go"
run_post "README.md"
check "post: extension outside quick_ext is skipped" 0

new_repo
write_cfg "quick=false" "quick_ext=go,ts"
run_post "web/x.ts"
check "post: quick_ext list matches second entry" 2

new_repo
write_cfg 'quick=test "{dir}" = sub' "quick_ext=go"
run_post "sub/a.go"
check "post: {dir} substitution (nested)" 0
run_post "a.go"
check "post: {dir} substitution (root is .)" 2

new_repo
write_cfg 'quick=test "{file}" = sub/a.go' "quick_ext=go"
run_post "sub/a.go"
check "post: {file} substitution" 0

new_repo
write_cfg "quick=false" "quick_ext=go"
run_post 'a;touch pwned.go'
check "post: unsafe path characters are skipped" 0
[ ! -e "$R/pwned.go" ] && [ ! -e "$R/pwned" ] || { FAIL=$((FAIL + 1)); echo "FAIL post: injection created a file"; }

new_repo
write_cfg "quick=false" "quick_ext=go"
git -C "$R" add -f .t4l/config
run_post "a.go"
check "post: tracked config is refused" 0 "is tracked by git"
T4L_TRUST_CONFIG=1 run_post "a.go"
check "post: tracked config runs with T4L_TRUST_CONFIG=1" 2

new_repo
write_cfg "quick=false" "quick_ext=go"
T4L_HOOKS=off run_post "a.go"
check "post: T4L_HOOKS=off disables" 0

new_repo
write_cfg "quick=false" "quick_ext=go" "disable=1"
run_post "a.go"
check "post: disable=1 disables" 0

new_repo
write_cfg "quick=false" "quick_ext=go"
T4L_NO_JQ=1 run_post "a.go"
check "post: works without jq (sed fallback)" 2 "t4l quick check failed"

new_repo
write_cfg "quick=sleep 5" "quick_ext=go" "quick_timeout=1"
run_post "a.go"
check "post: timeout counts as failure" 2 "exit 124"

new_repo
write_cfg "quick=false" "quick_ext=go"
OUT=$(printf '{"cwd":"%s","tool_input":{"file_path":"a.go"}}' "$TMP" | sh "$POST" 2>&1)
RC=$?
check "post: non-git directory is a no-op" 0

new_repo
write_cfg "quick=printf 'line%s\n' 1 2 3; false" "quick_ext=go"
run_post "a.go"
check "post: failure output is included" 2 "line3"

# --- stop-verify -----------------------------------------------------------

new_repo
write_cfg "verify=false"
run_stop
check "stop: clean tree skips verify" 0

new_repo
write_cfg "verify=false"
echo change >>"$R/base.txt"
run_stop
check "stop: dirty tree + failing verify exits 2" 2 "t4l verify failed"

new_repo
write_cfg "verify=true"
echo change >>"$R/base.txt"
run_stop
check "stop: dirty tree + passing verify is silent" 0

new_repo
write_cfg "verify=false"
echo change >>"$R/base.txt"
run_stop ',"stop_hook_active":true'
check "stop: stop_hook_active prevents a loop" 0

new_repo
echo change >>"$R/base.txt"
run_stop
check "stop: no config is a no-op" 0

new_repo
write_cfg "verify=false"
echo change >>"$R/base.txt"
T4L_HOOKS=off run_stop
check "stop: T4L_HOOKS=off disables" 0

new_repo
write_cfg "verify=printf 'boom\n'; false"
echo change >>"$R/base.txt"
run_stop
check "stop: failure output is included" 2 "boom"

new_repo
write_cfg "verify=false" "disable=1"
echo change >>"$R/base.txt"
run_stop
check "stop: disable=1 disables" 0

new_repo
write_cfg "verify=false"
echo change >"$R/untracked.txt"
run_stop
check "stop: untracked file counts as a change" 2

# --- session-start ---------------------------------------------------------

START="$HERE/hooks/session-start.sh"
mkdir -p "$TMP/cfg/rules" "$TMP/cfg-with-copy/rules"
echo copy >"$TMP/cfg-with-copy/rules/t4l.md"

OUT=$(CLAUDE_CONFIG_DIR="$TMP/cfg" sh "$START" 2>&1)
RC=$?
check "start: injects the kernel" 0 "# t4l kernel"
case $OUT in T4L_ROOT=*) ;; *) FAIL=$((FAIL + 1)); echo "FAIL start: first line announces T4L_ROOT" ;; esac

OUT=$(CLAUDE_CONFIG_DIR="$TMP/cfg-with-copy" sh "$START" 2>&1)
RC=$?
case $OUT in *"# t4l kernel"*) RC=1 ;; esac
check "start: kernel body skipped when ~/.claude/rules/t4l.md exists" 0 "T4L_ROOT="

OUT=$(T4L_KERNEL=off CLAUDE_CONFIG_DIR="$TMP/cfg" sh "$START" 2>&1)
RC=$?
case $OUT in *"# t4l kernel"*) RC=1 ;; esac
check "start: T4L_KERNEL=off skips the kernel body" 0 "T4L_ROOT="

# --- t4l-init --------------------------------------------------------------

# shellcheck disable=SC2120
init_in() { (cd "$R" && sh "$INIT" "$@" 2>&1); }

new_repo
rm -rf "$R/.t4l"
printf 'module x\n\ngo 1.22\n' >"$R/go.mod"
# shellcheck disable=SC2119
OUT=$(init_in)
RC=$?
CFG=$(cat "$R/.t4l/config")
case $CFG in
*"quick=go vet ./{dir} && go test ./{dir}"*"verify=go vet ./... && go test ./..."*) RC2=0 ;;
*) RC2=1 ;;
esac
RC=$((RC + RC2))
check "init: Go repo config" 0 "wrote"
if grep -qx '\.t4l/' "$R/.gitignore"; then
	PASS=$((PASS + 1))
	echo "ok   init: adds .t4l/ to .gitignore"
else
	FAIL=$((FAIL + 1))
	echo "FAIL init: .gitignore"
fi

if OUT=$(init_in); then RC=1; else RC=0; fi
check "init: refuses to overwrite without --force" 0 "already exists"

new_repo
rm -rf "$R/.t4l"
cat >"$R/package.json" <<'EOF'
{"name":"x","scripts":{"test":"vitest run","lint":"eslint .","typecheck":"tsc --noEmit"}}
EOF
touch "$R/pnpm-lock.yaml"
OUT=$(init_in)
RC=$?
case $(cat "$R/.t4l/config") in
*"quick_ext=ts,tsx,js,jsx,mts,cts"*"verify=pnpm run test && pnpm run lint && pnpm run typecheck"*) ;;
*) RC=1 ;;
esac
check "init: TS repo detects pnpm and scripts" 0 "wrote"

new_repo
rm -rf "$R/.t4l"
cat >"$R/package.json" <<'EOF'
{"name":"x","scripts":{"test":"echo \"Error: no test specified\" && exit 1"}}
EOF
OUT=$(init_in)
RC=$?
if ! grep -qx 'verify=' "$R/.t4l/config"; then RC=1; fi
check "init: skips the default npm placeholder test script" 0 "wrote"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
