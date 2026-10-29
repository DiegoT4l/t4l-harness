#!/bin/sh
# PreToolUse / PostToolUse (Bash): catch writes made through Bash that guard.sh
# would have refused through Edit or Write.
#
#   bash-guard.sh pre    snapshot the files git sees as changed, plus .t4l/
#   bash-guard.sh post   compare, and run every changed file through guard.sh
#
# It detects after the fact; it does not prevent. Files ignored by git (other
# than .t4l/) and writes from a background command are not seen. Revert is left
# to the agent. Same switches as guard.sh: only while a feature is open, off
# with T4L_GUARD=off.

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

[ "${T4L_GUARD:-}" = off ] && exit 0
mode=${1:-}

t4l_read_input
cwd=$(t4l_json '.cwd' cwd)
[ -n "$cwd" ] || cwd=$PWD
root=$(t4l_main_root "$cwd") || exit 0

# Snapshots live outside the repo, in a directory only this user can use.
dir="${TMPDIR:-/tmp}/t4l-bash-$(id -u)"
id=$(t4l_json '.tool_use_id' tool_use_id | tr -cd 'A-Za-z0-9_-')
[ -n "$id" ] || id=none
snap="$dir/$id"

if [ "$mode" = post ]; then
	[ -f "$snap" ] || exit 0
	before=$(cat "$snap")
	rm -f "$snap"
fi

state="$root/.t4l/state"
[ -f "$state" ] || exit 0
[ "$(sed -n 's/^phase=//p' "$state" | head -n 1)" = "done" ] && exit 0

# snapshot <root>...: "<hash> <absolute path>" for every file git reports as
# changed or untracked, and every file under .t4l/ except the worktrees and
# the reports, which every role may write.
# A deleted file hashes as "-".
snapshot() {
	for _r in "$@"; do
		{
			git -C "$_r" -c core.quotepath=off status --porcelain=v1 -uall 2>/dev/null |
				cut -c4- | sed 's/.* -> //'
			if [ -d "$_r/.t4l" ]; then
				(cd "$_r" && find .t4l \( -path .t4l/worktrees -o -path .t4l/reports \) -prune -o -type f -print)
			fi
		} | while IFS= read -r _p; do
			if [ -f "$_r/$_p" ]; then
				printf '%s %s\n' "$(git hash-object -- "$_r/$_p" 2>/dev/null || echo '?')" "$_r/$_p"
			else
				printf '%s %s\n' - "$_r/$_p"
			fi
		done
	done | sort -u
}

# snapshot_all: the main checkout, plus the worktree the command runs in.
work=$(t4l_repo_root "$cwd")
snapshot_all() {
	if [ -n "$work" ] && [ "$work" != "$root" ]; then
		snapshot "$root" "$work"
	else
		snapshot "$root"
	fi
}

if [ "$mode" = pre ]; then
	if [ ! -d "$dir" ]; then
		(umask 077 && mkdir -p "$dir") || exit 0
	fi
	# Refuse a directory someone else planted.
	[ ! -L "$dir" ] && [ -n "$(find "$dir" -prune -user "$(id -u)")" ] || exit 0
	# Drop snapshots left by commands that never reached post.
	find "$dir" -type f -mmin +1440 -exec rm -f {} + 2>/dev/null
	snapshot_all >"$snap"
	exit 0
fi

[ "$mode" = post ] || exit 0

after=$(snapshot_all)
changed=$(printf '%s\n%s\n' "$before" "$after" | sed '/^$/d' | sort | uniq -u |
	cut -d' ' -f2- | sort -u)
[ -n "$changed" ] || exit 0

agent_type=$(t4l_json '.agent_type' agent_type)
guard="$(dirname "$0")/guard.sh"

# json_str <text>: the text as a JSON string body.
json_str() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

denied=""
reason=""
nl='
'
while IFS= read -r f; do
	[ -n "$f" ] || continue
	input=$(printf '{"cwd":"%s","agent_type":"%s","tool_input":{"file_path":"%s"}}' \
		"$(json_str "$cwd")" "$(json_str "$agent_type")" "$(json_str "$f")")
	if ! msg=$(printf '%s' "$input" | sh "$guard" 2>&1); then
		denied="$denied  ${f#"$root"/}$nl"
		[ -n "$reason" ] || reason=$msg
	fi
done <<EOF
$changed
EOF

[ -n "$denied" ] || exit 0
{
	echo "t4l bash guard: this Bash command changed files that Edit and Write would have refused:"
	printf '%s' "$denied"
	echo "The rule it broke:"
	printf '%s\n' "$reason" | sed 's/^/  /'
	echo "Undo those changes (restore the previous content) and follow the rule instead of working around it with Bash."
	echo "If another agent running at the same time made them, or they are build output, say so and carry on."
} >&2
exit 2
