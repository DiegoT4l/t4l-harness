#!/bin/sh
# Tests for scripts/t4l-setup.sh. Run: sh tests/setup.sh

HERE=$(cd "$(dirname "$0")/.." && pwd)
SETUP="$HERE/scripts/t4l-setup.sh"

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

# A PATH that holds only what the test puts in it: the shell utilities the
# script needs, plus the tools under test as stubs or links.
BIN="$TMP/bin"
mkdir -p "$BIN"
for t in sh cat sed grep dirname; do
	ln -s "$(command -v "$t")" "$BIN/$t"
done
GIT=$(command -v git)
link_git() { ln -sf "$GIT" "$BIN/git"; }
stub() {
	for t in "$@"; do
		printf '#!/bin/sh\nexit 0\n' >"$BIN/$t"
		chmod +x "$BIN/$t"
	done
}

S() { # dir [env assignments...]
	_dir=$1
	shift
	OUT=$(cd "$_dir" && env -i HOME="$TMP" PATH="$BIN" "$@" sh "$SETUP" 2>&1)
	RC=$?
}

R="$TMP/repo"
mkdir -p "$R"
"$GIT" -C "$R" init -q -b main
"$GIT" -C "$R" config user.email t@example.com
"$GIT" -C "$R" config user.name t
NOREPO="$TMP/norepo"
mkdir -p "$NOREPO"

S "$NOREPO"
check "missing git is a failure" 1 "miss git"

link_git
S "$NOREPO"
check "git alone is enough" 0 "ok   git"
check "missing jq is reported with its fallback" 0 "miss jq"
check "outside a repository says so" 0 "not inside a git repository"

stub jq timeout
S "$NOREPO"
check "recommended tools found" 0 "ok   jq"
check "timeout found" 0 "ok   timeout"

S "$NOREPO"
check "absent optional tool shows how to install it" 0 "uv tool install 'markitdown[all]'"
stub claude gremlins ccc markitdown pi-worker engram
S "$NOREPO"
check "optional tools found" 0 "ok   gremlins"
check "journeys need the claude CLI" 0 "ok   claude"

S "$R"
check "repository without config: hooks off" 0 "verification hooks: off"
check "and how to turn them on" 0 "/t4l:init"

mkdir -p "$R/.t4l"
printf 'verify=true\n' >"$R/.t4l/config"
S "$R"
check "config present: hooks on" 0 "verification hooks: on"
S "$R" T4L_HOOKS=off
check "T4L_HOOKS=off turns them off" 0 "off (T4L_HOOKS=off)"
printf 'verify=true\ndisable=1\n' >"$R/.t4l/config"
S "$R"
check "disable=1 turns them off" 0 "off (disable=1"

printf 'verify=true\n' >"$R/.t4l/config"
"$GIT" -C "$R" add -f .t4l/config
"$GIT" -C "$R" commit -qm config
S "$R"
check "committed config is not trusted" 0 "T4L_TRUST_CONFIG=1"
S "$R" T4L_TRUST_CONFIG=1
check "trusted committed config: hooks on" 0 "verification hooks: on"

check "ccc installed but not enabled: how to enable it" 0 "t4l-search.sh --init"

mkdir -p "$R/.cocoindex_code"
: >"$R/.cocoindex_code/settings.yml"
S "$R"
check "ccc enabled in the repository" 0 "semantic search: enabled"

before=$(cd "$R" && "$GIT" status --porcelain --ignored)
S "$R"
after=$(cd "$R" && "$GIT" status --porcelain --ignored)
[ "$before" = "$after" ] && RC=0 || RC=1
check "read-only: the repository is unchanged" 0 ""

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
