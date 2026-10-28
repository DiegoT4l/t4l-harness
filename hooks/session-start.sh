#!/bin/sh
# SessionStart: tell the agent where the t4l plugin lives, which optional tools
# are available, whether a newer t4l release is out, and inject the kernel, so the plugin works without copying
# rules/t4l.md into ~/.claude/rules.
# The kernel body is skipped when that copy already exists (it would load twice)
# or when T4L_KERNEL=off. The plugin root line is always printed.

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

root=$(cd "$(dirname "$0")/.." && pwd)
echo "T4L_ROOT=$root (t4l scripts are in $root/scripts)"

t4l_read_input
cwd=$(t4l_json '.cwd' cwd)
[ -n "$cwd" ] || cwd=$PWD
main=$(t4l_main_root "$cwd" 2>/dev/null) || main=""

if command -v ccc >/dev/null 2>&1; then
	if [ -n "$main" ] && [ -f "$main/.cocoindex_code/settings.yml" ]; then
		echo "ccc: enabled in this repository. For conceptual code questions run: sh $root/scripts/t4l-search.sh \"<what you are looking for>\""
		# refresh the index in the background; a session must not wait for it
		if command -v setsid >/dev/null 2>&1; then
			(cd "$main" && setsid ccc index </dev/null >/dev/null 2>&1 &)
		fi
	else
		echo "ccc: installed but not enabled in this repository (enable with: sh $root/scripts/t4l-search.sh --init)"
	fi
fi
if command -v markitdown >/dev/null 2>&1; then
	echo "markitdown: installed. Convert documents the user gives you (docx, xlsx, pptx, html, epub...) with: sh $root/scripts/t4l-ingest.sh <file>"
fi

# one line when a newer release is cached; the fetch itself runs in the background
sh "$root/scripts/t4l-version.sh" --notice 2>/dev/null

[ "${T4L_KERNEL:-}" = off ] && exit 0

cfgdir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
[ -f "$cfgdir/rules/t4l.md" ] && exit 0
[ -f "$root/rules/t4l.md" ] || exit 0

echo
echo "The t4l plugin injected the kernel below. Follow it for this session; the t4l skill holds the full procedure."
echo
cat "$root/rules/t4l.md"
