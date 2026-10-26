#!/bin/sh
# SessionStart: tell the agent where the t4l plugin lives and inject the kernel,
# so the plugin works without copying rules/t4l.md into ~/.claude/rules.
# The kernel body is skipped when that copy already exists (it would load twice)
# or when T4L_KERNEL=off. The plugin root line is always printed.

root=$(cd "$(dirname "$0")/.." && pwd)
echo "T4L_ROOT=$root (t4l scripts are in $root/scripts)"

[ "${T4L_KERNEL:-}" = off ] && exit 0

cfgdir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
[ -f "$cfgdir/rules/t4l.md" ] && exit 0
[ -f "$root/rules/t4l.md" ] || exit 0

echo
echo "The t4l plugin injected the kernel below. Follow it for this session; the t4l skill holds the full procedure."
echo
cat "$root/rules/t4l.md"
