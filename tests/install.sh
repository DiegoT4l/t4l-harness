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
PROJ="$TMP/proj"
mkdir -p "$PROJ"

I() { # [env assignments...] -- [args...]
	_env=""
	while [ $# -gt 0 ] && [ "$1" != -- ]; do
		_env="$_env $1"
		shift
	done
	[ $# -gt 0 ] && shift
	: >"$LOG"
	# shellcheck disable=SC2086  # _env holds plain VAR=value words
	OUT=$(cd "$PROJ" && env -i HOME="$TMP" PATH="$BIN" $_env sh "$INSTALL" "$@" 2>&1)
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

# --- auto-update -----------------------------------------------------------------

# the settings entry claude plugin marketplace add writes
seed() { # file
	mkdir -p "$(dirname "$1")"
	printf '{"model":"x","extraKnownMarketplaces":{"t4l-harness":{"source":{"source":"github","repo":"DiegoT4l/t4l-harness"}}}}\n' >"$1"
}
USER_SETTINGS="$TMP/.claude/settings.json"

seed "$USER_SETTINGS"
I --
check "without jq it says how to turn auto-update on" 0 "Enable auto-update"
grep -q autoUpdate "$USER_SETTINGS" && RC=1 || RC=0
check "without jq the settings stay untouched" 0 ""

ln -s "$(command -v jq)" "$BIN/jq"
for t in mv rm dirname; do ln -s "$(command -v "$t")" "$BIN/$t"; done
I --
check "turns auto-update on" 0 "auto-update: on"
OUT=$(jq -c '.extraKnownMarketplaces["t4l-harness"]' "$USER_SETTINGS")
check "in the user settings entry" 0 '"autoUpdate":true'
OUT=$(jq -r .model "$USER_SETTINGS")
check "keeps the other settings" 0 "x"
OUT=$(jq -r '.extraKnownMarketplaces["t4l-harness"].source.repo' "$USER_SETTINGS")
check "keeps the marketplace source" 0 "DiegoT4l/t4l-harness"

mkdir -p "$TMP/dotfiles"
seed "$TMP/dotfiles/settings.json"
ln -sf "$TMP/dotfiles/settings.json" "$USER_SETTINGS"
I --
[ -L "$USER_SETTINGS" ] && RC=0 || RC=1
check "a symlinked settings.json stays a symlink" 0 ""
OUT=$(jq -c '.extraKnownMarketplaces["t4l-harness"]' "$TMP/dotfiles/settings.json")
check "and its target gets the change" 0 '"autoUpdate":true'
rm -f "$USER_SETTINGS"

seed "$PROJ/.claude/settings.json"
I -- --scope project
OUT=$(jq -c '.extraKnownMarketplaces["t4l-harness"]' "$PROJ/.claude/settings.json")
check "--scope project writes the project settings" 0 '"autoUpdate":true'
seed "$PROJ/.claude/settings.local.json"
I -- --scope local
OUT=$(jq -c '.extraKnownMarketplaces["t4l-harness"]' "$PROJ/.claude/settings.local.json")
check "--scope local writes the local settings" 0 '"autoUpdate":true'

seed "$USER_SETTINGS"
I -- --no-auto-update
grep -q autoUpdate "$USER_SETTINGS" && RC=1 || RC=0
check "--no-auto-update leaves it off" 0 ""
check "and says so" 0 "auto-update: left off"

printf '{"model":"x"}\n' >"$USER_SETTINGS"
I --
check "no marketplace entry: no settings invented" 0 "Enable auto-update"
OUT=$(jq -c . "$USER_SETTINGS")
check "the file is unchanged" 0 '{"model":"x"}'

I -- --help
check "--help prints the usage" 0 "curl -fsSL"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
