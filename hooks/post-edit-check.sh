#!/bin/sh
# PostToolUse (Edit|Write): run the repo's quick check after a file edit.
# Silent on success. On failure, exit 2 so the output reaches the agent.

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

[ "${T4L_HOOKS:-}" = off ] && exit 0

t4l_read_input
cwd=$(t4l_json '.cwd' cwd)
[ -n "$cwd" ] || cwd=$PWD
main=$(t4l_main_root "$cwd") || exit 0
t4l_load_config "$main" || exit 0
[ -n "$CFG_QUICK" ] || exit 0

file=$(t4l_json '.tool_input.file_path' file_path)
[ -n "$file" ] || exit 0
case $file in
/*) abs=$file ;;
*) abs=$cwd/$file ;;
esac
work=$(t4l_repo_root "$(t4l_existing_dir "$(dirname "$abs")")") || exit 0
case $abs in
"$work"/*) rel=${abs#"$work"/} ;;
*) exit 0 ;;
esac
t4l_safe_path "$rel" || exit 0

if [ -n "$CFG_QUICK_EXT" ]; then
	ext=${rel##*.}
	case ",$CFG_QUICK_EXT," in
	*",$ext,"*) ;;
	*) exit 0 ;;
	esac
fi

dir=$(dirname "$rel")
cmd=$(printf '%s' "$CFG_QUICK" | sed "s|{dir}|$dir|g; s|{file}|$rel|g")

out=$(t4l_run "$work" "$CFG_QUICK_TIMEOUT" "$cmd")
rc=$?
[ "$rc" -eq 0 ] && exit 0

{
	printf 't4l quick check failed (exit %s) after editing %s\n$ %s\n' "$rc" "$rel" "$cmd"
	printf '%s\n' "$out" | tail -n 40
} >&2
exit 2
