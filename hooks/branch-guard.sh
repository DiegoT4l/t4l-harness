#!/bin/sh
# PreToolUse (Bash): refuse `git commit` while the current branch is protected.
#
# Opt-in per repository: it only acts when .t4l/config sets
#   protected_branches=main,master
# A command that creates a branch first (git switch -c, git checkout -b) is
# allowed. The user can override by starting the session with T4L_ALLOW_PROTECTED=1
# (an inline prefix on the command does not count); T4L_HOOKS=off turns it off.

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

[ "${T4L_HOOKS:-}" = off ] && exit 0
[ "${T4L_ALLOW_PROTECTED:-}" = 1 ] && exit 0

t4l_read_input
cmd=$(t4l_json '.tool_input.command' command)
[ -n "$cmd" ] || exit 0

# Does the command run `git [options] commit`? Walk each shell segment.
is_commit=$(printf '%s\n' "$cmd" | awk '
	{
		n = split($0, segs, /[;&|]+/)
		for (s = 1; s <= n; s++) {
			gsub(/[()]/, " ", segs[s])
			m = split(segs[s], f, /[ \t]+/)
			i = 1
			while (i <= m && (f[i] == "" || f[i] ~ /=/)) i++
			if (f[i] == "git" || f[i] ~ /\/git$/) {
				j = i + 1
				while (j <= m && f[j] ~ /^-/) {
					if (f[j] == "-C" || f[j] == "-c" || f[j] == "--git-dir" || f[j] == "--work-tree") j++
					j++
				}
				if (f[j] == "commit") { print 1; exit }
			}
		}
	}')
[ "$is_commit" = 1 ] || exit 0

# A command that creates its own branch first is fine.
if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+(switch[[:space:]]+(-c|--create)|checkout[[:space:]]+-[bB])'; then
	exit 0
fi

cwd=$(t4l_json '.cwd' cwd)
[ -n "$cwd" ] || cwd=$PWD
main=$(t4l_main_root "$cwd") || exit 0
t4l_load_config "$main" || exit 0
[ -n "$CFG_PROTECTED" ] || exit 0

branch=$(git -C "$cwd" symbolic-ref --quiet --short HEAD 2>/dev/null) || exit 0
case ",$CFG_PROTECTED," in
*",$branch,"*)
	{
		echo "t4l branch guard: '$branch' is a protected branch, so commits to it are blocked."
		echo "Create a branch first, for example: git switch -c <type>/<short-name>"
		echo "Do not try to bypass this. If the user really wants a commit on '$branch', tell them to start the session with T4L_ALLOW_PROTECTED=1 (an inline prefix on the command is not honored) and ask what they prefer."
	} >&2
	exit 2
	;;
esac
exit 0
