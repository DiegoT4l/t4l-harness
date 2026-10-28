#!/bin/sh
# Tests for scripts/t4l-version.sh. Run: sh tests/version.sh

HERE=$(cd "$(dirname "$0")/.." && pwd)

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

# An installed plugin is a copy without .git; the script finds its version in
# ../.claude-plugin/plugin.json and the latest one at T4L_LATEST_URL.
P="$TMP/plugin"
mkdir -p "$P/scripts" "$P/.claude-plugin"
cp "$HERE/scripts/t4l-version.sh" "$P/scripts/"
installed() { printf '{\n  "name": "t4l",\n  "version": "%s"\n}\n' "$1" >"$P/.claude-plugin/plugin.json"; }
latest() { printf '{\n  "name": "t4l",\n  "version": "%s"\n}\n' "$1" >"$TMP/latest.json"; }
DATA="$TMP/data"
CFG="$TMP/cfg"
mkdir -p "$CFG"

V() {
	OUT=$(cd "$TMP" && CLAUDE_PLUGIN_DATA="$DATA" CLAUDE_CONFIG_DIR="$CFG" T4L_LATEST_URL="file://$TMP/latest.json" \
		sh "$P/scripts/t4l-version.sh" "$@" 2>&1)
	RC=$?
}

installed 1.1.0
latest 1.2.0
V
check "newer release: update available" 1 "1.1.0 -> 1.2.0"
check "and how to update" 1 "claude plugin update t4l@t4l-harness"

latest 1.1.0
V
check "same version: up to date" 0 "up to date (1.1.0)"
latest 1.0.9
V
check "older release is not an update" 0 "up to date"
installed 1.9.0
latest 1.10.0
V
check "versions compare as numbers" 1 "1.9.0 -> 1.10.0"

OUT=$(cd "$TMP" && CLAUDE_PLUGIN_DATA="$DATA" CLAUDE_CONFIG_DIR="$CFG" T4L_LATEST_URL="file://$TMP/missing.json" \
	sh "$P/scripts/t4l-version.sh" 2>&1)
RC=$?
check "unreachable source: cannot check" 2 "could not check"

# --- auto-update status -------------------------------------------------------

V
check "auto-update off by default" 1 "auto-update: off"
printf '{"extraKnownMarketplaces":{"t4l-harness":{"source":{"source":"github","repo":"DiegoT4l/t4l-harness"},"autoUpdate":true}}}\n' >"$CFG/settings.json"
V
check "auto-update on in user settings" 1 "auto-update: on"
check "auto-update on: no manual update line" 1 "installs it in the background"
printf '{"extraKnownMarketplaces":{"t4l-harness":{"autoUpdate":false}}}\n' >"$CFG/settings.json"
mkdir -p "$CFG/plugins"
printf '{"t4l-harness":{"autoUpdate":true}}\n' >"$CFG/plugins/known_marketplaces.json"
V
check "settings win over the /plugin toggle" 1 "auto-update: off"
printf '{}\n' >"$CFG/settings.json"
V
check "the /plugin toggle counts when settings say nothing" 1 "auto-update: on"
rm -f "$CFG/settings.json" "$CFG/plugins/known_marketplaces.json"

# --- cache: --refresh and --notice ----------------------------------------------

installed 1.1.0
latest 1.2.0
V --refresh
check "--refresh is silent" 0 ""
[ -f "$DATA/latest-version" ] && RC=0 || RC=1
check "--refresh writes the cache" 0 ""

V --notice
check "--notice reads the cache" 0 "t4l 1.2.0 is available (this session runs 1.1.0)"

latest 1.1.0
V --refresh
V --notice
[ -z "$OUT" ] && RC=0 || RC=1
check "--notice is silent when up to date" 0 ""

rm -rf "$DATA"
latest 1.3.0
V --notice
[ -z "$OUT" ] && RC=0 || RC=1
check "--notice without a cache prints nothing" 0 ""
i=0
while [ ! -f "$DATA/latest-version" ] && [ $i -lt 50 ]; do
	sleep 0.1
	i=$((i + 1))
done
grep -q ' 1.3.0$' "$DATA/latest-version" 2>/dev/null && RC=0 || RC=1
check "--notice refreshes a missing cache in the background" 0 ""

printf '1 1.2.0\n' >"$DATA/latest-version"
latest 1.4.0
V --notice
check "a stale cache is still shown" 0 "t4l 1.2.0 is available"
i=0
while ! grep -q ' 1.4.0$' "$DATA/latest-version" 2>/dev/null && [ $i -lt 50 ]; do
	sleep 0.1
	i=$((i + 1))
done
grep -q ' 1.4.0$' "$DATA/latest-version" && RC=0 || RC=1
check "and refreshed in the background" 0 ""

OUT=$(cd "$TMP" && CLAUDE_PLUGIN_DATA="$DATA" CLAUDE_CONFIG_DIR="$CFG" T4L_UPDATE_CHECK=off \
	sh "$P/scripts/t4l-version.sh" --notice 2>&1)
RC=$?
[ -z "$OUT" ] && RC=0 || RC=1
check "T4L_UPDATE_CHECK=off silences --notice" 0 ""

mkdir -p "$P/.git"
V --notice
[ -z "$OUT" ] && RC=0 || RC=1
check "a git checkout (--plugin-dir) gets no notice" 0 ""
rmdir "$P/.git"

V --nope
check "unknown option is a usage error" 2 "Usage"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
