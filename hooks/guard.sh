#!/bin/sh
# PreToolUse (Edit|Write): enforce the large-lane rules from .t4l/state.
#
#  - gate=pending: the specs are not approved, nobody writes outside .t4l/.
#  - phase=implementing: the lead does not write; subagents (agent_type set) do.
#  - t4l:judge and t4l:reviewer are read-only: they may write only .t4l/reports/.
#
# Only active while a feature is open (.t4l/state exists and phase != done).
# Covers Edit and Write. Writes made through Bash are caught after the fact by
# bash-guard.sh, which reuses these rules. Off with T4L_GUARD=off.

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

[ "${T4L_GUARD:-}" = off ] && exit 0

t4l_read_input
cwd=$(t4l_json '.cwd' cwd)
[ -n "$cwd" ] || cwd=$PWD
root=$(t4l_main_root "$cwd") || exit 0
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

# State and reports live in the main checkout, never in a worktree's own .t4l/.
case $abs in
"$root"/.t4l/*) ;;
*/.t4l/*)
	echo "t4l guard: .t4l/ files live in the main checkout, not inside a worktree. Write to $root/.t4l/${abs#*/.t4l/} instead (t4l-task.sh where prints the paths)." >&2
	exit 2
	;;
esac

agent_type=$(t4l_json '.agent_type' agent_type)

# matches_files <path> <comma-separated globs>: 0 when the path matches a glob.
# The globs are patterns: they must never be expanded against the filesystem,
# or a glob like dir/** turns into the name of a file that already exists there.
matches_files() {
	_mf_ifs=$IFS
	IFS=','
	set -f
	for _mf_g in $2; do
		# shellcheck disable=SC2254  # the glob is meant to be a pattern
		case $1 in $_mf_g)
			set +f
			IFS=$_mf_ifs
			return 0
			;;
		esac
	done
	set +f
	IFS=$_mf_ifs
	return 1
}

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

if [ "$phase" = implementing ] && [ -n "$agent_type" ]; then
	deny() {
		{
			echo "t4l guard: $1"
			echo "${2:-}"
		} >&2
		exit 2
	}
	case $agent_type in
	t4l:workflow-master)
		case $abs in
		"$root"/.t4l/worktrees/integration/*) exit 0 ;;
		esac
		deny "the workflow-master does not edit project files." "It writes reports under .t4l/ and resolves conflicts only inside .t4l/worktrees/integration/. Delegate code changes to t4l:implementer."
		;;
	t4l:implementer)
		work=$(t4l_repo_root "$(t4l_existing_dir "$(dirname "$abs")")") || exit 0
		if [ "$work" = "$root" ]; then
			if [ "$(state_get parallel)" = 1 ]; then
				deny "parallel mode is on, so implementers must work in an isolated worktree, not in the main checkout." "Launch the implementer with isolation: worktree."
			fi
			exit 0
		fi
		task=""
		files=""
		for envf in "$root"/.t4l/board/*.env; do
			[ -f "$envf" ] || continue
			[ "$(sed -n 's/^worktree=//p' "$envf")" = "$work" ] || continue
			task=$(sed -n 's/^task=//p' "$envf")
			files=$(sed -n 's/^files=//p' "$envf")
		done
		if [ -z "$task" ]; then
			deny "this worktree has no task. Run: t4l-task.sh start <TASK> from inside it before editing." "Worktree: $work"
		fi
		if [ -z "$files" ] || [ "$files" = "-" ]; then
			exit 0
		fi
		rel=${abs#"$work"/}
		matches_files "$rel" "$files" && exit 0
		owner=""
		for envf in "$root"/.t4l/board/*.env; do
			[ -f "$envf" ] || continue
			ot=$(sed -n 's/^task=//p' "$envf")
			[ "$ot" = "$task" ] && continue
			matches_files "$rel" "$(sed -n 's/^files=//p' "$envf")" && owner="$ot"
		done
		msg="$rel is outside the files of $task ($files)."
		[ -n "$owner" ] && msg="$msg It belongs to $owner."
		deny "$msg" "Do not edit it. Report the file and why you need it; the lead or the workflow-master can amend Files in the feature document."
		;;
	esac
fi

exit 0
