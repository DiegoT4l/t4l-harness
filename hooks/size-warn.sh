#!/bin/sh
# PostToolUse (Edit|Write): warn once when a task's slice reaches 80% of the budget.
#
# Only for files inside a worktree registered to a task (.t4l/board/<TASK>.env).
# The warning is advisory: it reaches the agent as feedback, it does not block.
# Off with T4L_HOOKS=off.

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

[ "${T4L_HOOKS:-}" = off ] && exit 0

t4l_read_input
cwd=$(t4l_json '.cwd' cwd)
[ -n "$cwd" ] || cwd=$PWD
main=$(t4l_main_root "$cwd") || exit 0
[ -d "$main/.t4l/board" ] || exit 0

file=$(t4l_json '.tool_input.file_path' file_path)
[ -n "$file" ] || exit 0
case $file in
/*) abs=$file ;;
*) abs=$cwd/$file ;;
esac
work=$(t4l_repo_root "$(t4l_existing_dir "$(dirname "$abs")")") || exit 0

task=""
base=""
for envf in "$main"/.t4l/board/*.env; do
	[ -f "$envf" ] || continue
	[ "$(sed -n 's/^worktree=//p' "$envf")" = "$work" ] || continue
	task=$(sed -n 's/^task=//p' "$envf")
	base=$(sed -n 's/^base=//p' "$envf")
done
[ -n "$task" ] && [ -n "$base" ] || exit 0
[ -f "$main/.t4l/board/$task.warned" ] && exit 0

budget=400
if [ -f "$main/.t4l/config" ]; then
	_b=$(sed -n 's/^slice_budget=//p' "$main/.t4l/config" | head -n 1)
	[ -n "$_b" ] && budget=$_b
fi

size=$(cd "$work" && sh "$(dirname "$0")/../scripts/t4l-size.sh" --base "$base" --budget "$budget" --quiet 2>/dev/null)
case $size in '' | *[!0-9]*) exit 0 ;; esac
[ $((size * 100)) -ge $((budget * 80)) ] || exit 0

: >"$main/.t4l/board/$task.warned"
{
	echo "t4l size warning: $task is at $size of $budget lines (80% of the slice budget)."
	echo "Finish the current behavior with its tests and stop. If more work is needed, report it so the lead or the workflow-master can split it into another task."
} >&2
exit 2
