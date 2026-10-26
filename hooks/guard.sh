#!/bin/sh
# PreToolUse (Edit|Write): enforce the large-lane rules from .t4l/state.
#
#  - gate=pending: the specs are not approved, nobody writes outside .t4l/.
#  - phase=implementing: the lead does not write; subagents (agent_type set) do.
#  - t4l:judge and t4l:reviewer are read-only: they may write only .t4l/reports/.
#
# Only active while a feature is open (.t4l/state exists and phase != done).
# Covers Edit and Write, not writes made through Bash. Off with T4L_GUARD=off.

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

[ "${T4L_GUARD:-}" = off ] && exit 0

t4l_read_input
cwd=$(t4l_json '.cwd' cwd)
[ -n "$cwd" ] || cwd=$PWD
root=$(t4l_repo_root "$cwd") || exit 0
state="$root/.t4l/state"
[ -f "$state" ] || exit 0

state_get() { sed -n "s/^$1=//p" "$state" | head -n 1; }
phase=$(state_get phase)
gate=$(state_get gate)
feature=$(state_get feature)
[ "$phase" = "done" ] && exit 0

file=$(t4l_json '.tool_input.file_path' file_path)
[ -n "$file" ] || exit 0
case $file in
/*) abs=$file ;;
*) abs=$cwd/$file ;;
esac
case $abs in
"$root"/*) ;;
*) exit 0 ;;
esac

agent_type=$(t4l_json '.agent_type' agent_type)

# Read-only roles may only write their reports.
case $agent_type in
t4l:judge | t4l:reviewer)
	case $abs in
	"$root"/.t4l/reports/*) exit 0 ;;
	esac
	echo "t4l guard: $agent_type is read-only. Write only to .t4l/reports/ and report problems instead of fixing them." >&2
	exit 2
	;;
esac

case $abs in
"$root"/.t4l/*) exit 0 ;;
esac

if [ "$gate" = pending ]; then
	{
		echo "t4l guard: the specs of '$feature' are not approved yet, so nothing outside .t4l/ can be written."
		echo "Write the specs in .t4l/tasks/$feature.md, show them to the user and wait for approval."
		echo "After the user approves, run: t4l-task.sh approve"
	} >&2
	exit 2
fi

if [ "$phase" = implementing ] && [ -z "$agent_type" ]; then
	{
		echo "t4l guard: feature '$feature' is in the large lane, so the lead does not edit project files."
		echo "Delegate the task to the t4l:implementer agent (pass the path of .t4l/tasks/$feature.md and the task ID)."
		echo "To bypass deliberately, set T4L_GUARD=off."
	} >&2
	exit 2
fi

exit 0
