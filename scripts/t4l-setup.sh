#!/bin/sh
# Check this machine for what t4l uses and say which features are active.
# Read-only: it installs nothing and writes nothing. Run it from a repository
# to also see whether that repository has the verification hooks on.
#
# Usage: t4l-setup.sh
# Exit status: 0 when every required tool is present, 1 otherwise.

set -u

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../hooks/lib.sh
. "$here/../hooks/lib.sh"

missing=0

# tool <required|recommended|optional> <name> <what it enables> <install hint>
tool() {
	if command -v "$2" >/dev/null 2>&1; then
		printf 'ok   %-12s %s\n' "$2" "$3"
	else
		[ "$1" = required ] && missing=1
		printf 'miss %-12s %s -> %s\n' "$2" "$3" "$4"
	fi
}

echo "Required"
tool required git "everything: task state, worktrees, verification" "install git"

echo
echo "Recommended"
tool recommended jq "hook input parsing (a sed fallback covers the hooks), journeys, mutation, packaging" "install jq"
tool recommended timeout "time limits for verification commands (without it they run unbounded)" "install GNU coreutils"

echo
echo "Optional"
tool optional claude "journeys (t4l-journey.sh replays headless sessions)" "install Claude Code"
tool optional gremlins "mutation testing of changed Go code (t4l-mutate.sh)" "go install github.com/go-gremlins/gremlins/cmd/gremlins@v0.6.0"
tool optional ccc "semantic code search (t4l-search.sh)" "uv tool install 'cocoindex-code[full]'"
tool optional markitdown "document ingestion (t4l-ingest.sh)" "uv tool install 'markitdown[all]'"
tool optional pi-worker "mechanical bulk work delegated to Pi workers" "install the pi-workers skill"
tool optional engram "cross-session memory and the feature document mirror" "install the Engram plugin"

echo
echo "Version"
sh "$here/t4l-version.sh"

echo
echo "This repository"
if root=$(t4l_main_root "$PWD" 2>/dev/null) && [ -n "$root" ]; then
	echo "root: $root"
	if [ ! -f "$root/.t4l/config" ]; then
		echo "verification hooks: off (no .t4l/config; run /t4l:init to turn them on)"
	elif [ "${T4L_HOOKS:-}" = off ]; then
		echo "verification hooks: off (T4L_HOOKS=off)"
	elif err=$(t4l_load_config "$root" 2>&1); then
		echo "verification hooks: on (.t4l/config)"
	elif [ -n "$err" ]; then
		echo "verification hooks: off (.t4l/config is tracked by git; set T4L_TRUST_CONFIG=1 to allow it)"
	else
		echo "verification hooks: off (disable=1 in .t4l/config)"
	fi
	if [ -f "$root/.cocoindex_code/settings.yml" ]; then
		echo "semantic search: enabled"
	elif command -v ccc >/dev/null 2>&1; then
		echo "semantic search: not enabled (enable it with: sh $here/t4l-search.sh --init)"
	else
		echo "semantic search: not enabled (ccc is not installed)"
	fi
else
	echo "not inside a git repository: run it from one to check its .t4l/config"
fi

exit "$missing"
