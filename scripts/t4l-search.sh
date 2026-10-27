#!/bin/sh
# Semantic code search with cocoindex-code (ccc), from the main checkout or from
# a linked worktree. Results are leads: verify them by reading the files.
#
# Usage: t4l-search.sh [ccc search options] <query...>
#        t4l-search.sh --init
#   --init        enable ccc in this repository: project settings, first index.
#                 The repository's tracked .gitignore is left untouched; the index
#                 directory is ignored through .git/info/exclude instead.
#   Options such as --limit N, --offset N, --lang L and --path GLOB go to ccc.
# The search always runs against the main checkout's index and refreshes it first.
# From a worktree, result paths are relative to the repository root and are the
# same inside the worktree.
# Exit status: 0 results, 1 no results, 2 ccc missing or failed, 3 ccc not enabled here.

set -u

usage() {
	sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 2
}

command -v ccc >/dev/null 2>&1 || {
	echo "t4l-search: ccc is not installed. Install it with: uv tool install 'cocoindex-code[full]'" >&2
	exit 2
}

gc=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || {
	echo "t4l-search: not inside a git repository" >&2
	exit 2
}
case $gc in
*/.git) main=$(dirname "$gc") ;;
*) main=$(git rev-parse --show-toplevel) ;;
esac
here=$(git rev-parse --show-toplevel)

if [ "${1:-}" = "--init" ]; then
	cd "$main" || exit 2
	gi_tracked=0
	gi_clean=1
	gi_existed=0
	[ -f .gitignore ] && gi_existed=1
	git ls-files --error-unmatch .gitignore >/dev/null 2>&1 && gi_tracked=1
	if [ "$gi_tracked" -eq 1 ] && ! git diff --quiet -- .gitignore; then gi_clean=0; fi

	ccc init </dev/null >/dev/null 2>&1 || {
		echo "t4l-search: ccc init failed; run 'ccc doctor' for details" >&2
		exit 2
	}

	# undo ccc's edit of the tracked .gitignore when we can do it safely
	if [ "$gi_tracked" -eq 1 ] && [ "$gi_clean" -eq 1 ]; then
		git checkout -q -- .gitignore
	elif [ "$gi_existed" -eq 0 ] && [ -f .gitignore ]; then
		rm -f .gitignore
	elif [ "$gi_tracked" -eq 1 ]; then
		echo "t4l-search: .gitignore had uncommitted changes, so ccc's lines were left in it" >&2
	fi
	mkdir -p "$gc/info"
	grep -qx '/.cocoindex_code/' "$gc/info/exclude" 2>/dev/null || printf '/.cocoindex_code/\n' >>"$gc/info/exclude"

	ccc index </dev/null 2>&1 | tail -n 8
	exit 0
fi

[ -f "$main/.cocoindex_code/settings.yml" ] || {
	echo "t4l-search: ccc is not enabled in this repository. Enable it with: t4l-search.sh --init (indexes locally; the first run downloads the embedding model)." >&2
	exit 3
}

[ $# -ge 1 ] || usage

out=$(cd "$main" && ccc search --refresh "$@" </dev/null 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then
	printf '%s\n' "$out" >&2
	exit 2
fi
case $out in
*"No results found"*)
	echo "No results found."
	exit 1
	;;
esac
printf '%s\n' "$out"
if [ "$here" != "$main" ]; then
	echo
	echo "(paths are relative to the repository root; in this worktree they live under $here/)"
fi
exit 0
