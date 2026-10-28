#!/bin/sh
# Tests for scripts/t4l-package.sh. Run: sh tests/package.sh

HERE=$(cd "$(dirname "$0")/.." && pwd)
PACKAGE="$HERE/scripts/t4l-package.sh"

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

R="$TMP/repo"
mkdir -p "$R/.claude-plugin" "$R/rules" "$R/skills/t4l" "$R/agents" "$R/hooks" "$R/scripts" "$R/tests" "$R/docs"
git -C "$R" init -q -b main
git -C "$R" config user.email t@example.com
git -C "$R" config user.name t
echo '{"name":"t4l","version":"1.2.3"}' >"$R/.claude-plugin/plugin.json"
for f in rules/t4l.md skills/t4l/SKILL.md agents/judge.md hooks/hooks.json scripts/t4l-task.sh tests/x.sh docs/d.md README.md; do
	echo x >"$R/$f"
done
git -C "$R" add -A
git -C "$R" commit -qm base

P() {
	OUT=$(cd "$R" && sh "$PACKAGE" "$@" 2>&1)
	RC=$?
}

P --out "$TMP/out"
check "builds t4l-<version>.zip" 0 "$TMP/out/t4l-1.2.3.zip"
OUT=$(unzip -l "$TMP/out/t4l-1.2.3.zip")
RC=0
check "zip holds the runtime files" 0 "skills/t4l/SKILL.md"
case $OUT in *tests/* | *docs/*) RC=1 ;; esac
check "zip leaves out tests and docs" 0 ""

P --out "$TMP/out" --expect v1.2.3
check "expect accepts a v-prefixed tag" 0 "t4l-1.2.3.zip"
P --out "$TMP/out" --expect 1.2.4
check "version mismatch fails" 1 "says 1.2.3, expected 1.2.4"

echo '{"name":"t4l","version":"1.3.0"}' >"$R/.claude-plugin/plugin.json"
P --out "$TMP/out"
check "uncommitted changes are not packaged" 0 "t4l-1.2.3.zip"
git -C "$R" commit -qam bump
P --out "$TMP/out" --ref HEAD~1
check "--ref packages an older commit" 0 "t4l-1.2.3.zip"

P --ref nosuchref
check "unknown ref is a setup error" 2 "unknown ref"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
