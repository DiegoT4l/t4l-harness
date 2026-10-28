#!/bin/sh
# Tests for install.sh. Run: sh tests/install.sh

HERE=$(cd "$(dirname "$0")/.." && pwd)
INSTALL="$HERE/install.sh"

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

# A PATH with the shell utilities the installer needs and a fake claude that
# logs each call and fails when FAKE_FAIL is one of its words.
BIN="$TMP/bin"
mkdir -p "$BIN"
for t in sh cat; do
	ln -s "$(command -v "$t")" "$BIN/$t"
done
LOG="$TMP/calls"
cat >"$TMP/claude" <<EOF
#!/bin/sh
echo "\$*" >>"$LOG"
case "\$*" in
*" \${FAKE_FAIL:-none} "*) echo "boom" >&2; exit 1 ;;
esac
exit 0
EOF
chmod +x "$TMP/claude"
with_claude() { ln -sf "$TMP/claude" "$BIN/claude"; }

I() { # [env assignments...] -- [args...]
	_env=""
	while [ $# -gt 0 ] && [ "$1" != -- ]; do
		_env="$_env $1"
		shift
	done
	[ $# -gt 0 ] && shift
	: >"$LOG"
	# shellcheck disable=SC2086  # _env holds plain VAR=value words
	OUT=$(env -i HOME="$TMP" PATH="$BIN" $_env sh "$INSTALL" "$@" 2>&1)
	RC=$?
	CALLS=$(cat "$LOG" 2>/dev/null)
}

I --
check "without claude it fails and says where to get it" 1 "Claude Code"

with_claude
I --
check "installs" 0 "installed t4l"
OUT=$CALLS
check "adds the marketplace from GitHub" 0 "plugin marketplace add DiegoT4l/t4l-harness --scope user"
check "refreshes it" 0 "plugin marketplace update t4l-harness"
check "installs the plugin" 0 "plugin install t4l@t4l-harness --scope user"
check "updates an existing install" 0 "plugin update t4l@t4l-harness --scope user"

I -- --scope project
OUT=$CALLS
check "--scope reaches every call" 0 "plugin install t4l@t4l-harness --scope project"
I T4L_SCOPE=local --
OUT=$CALLS
check "T4L_SCOPE sets the scope" 0 "plugin install t4l@t4l-harness --scope local"
I -- --scope global
check "unknown scope is a usage error" 2 "user, project or local"
I -- --nope
check "unknown option is a usage error" 2 "Usage"

I -- --marketplace ./local/checkout
OUT=$CALLS
check "--marketplace picks another source" 0 "plugin marketplace add ./local/checkout"

I FAKE_FAIL=install --
check "a failing step stops the install" 1 "boom"
OUT=$CALLS
case $OUT in *"plugin update"*) RC=1 ;; *) RC=0 ;; esac
check "nothing runs after the failure" 0 ""

I -- --help
check "--help prints the usage" 0 "curl -fsSL"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
