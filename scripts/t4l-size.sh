#!/bin/sh
# Measure the authored size of a change: added plus deleted lines between a base
# ref and the working tree (committed, uncommitted and untracked files), leaving
# out generated files, lockfiles and tool directories.
#
# Usage: t4l-size.sh [--base REF] [--budget N] [--files] [--quiet]
#   --base REF    previous code to compare against (default: HEAD)
#   --budget N    slice budget in lines (default: slice_budget in .t4l/config, else 400)
#   --files       also list the largest files
#   --quiet       print only the number
# Run it from the repository or worktree to measure.
# Exit status: 0 within budget, 1 over budget, 2 usage or setup error.

set -u

base=HEAD
budget=""
files=0
quiet=0

usage() {
	sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 2
}

while [ $# -gt 0 ]; do
	case $1 in
	--base)
		[ $# -ge 2 ] || usage
		base=$2
		shift 2
		;;
	--budget)
		[ $# -ge 2 ] || usage
		budget=$2
		shift 2
		;;
	--files)
		files=1
		shift
		;;
	--quiet)
		quiet=1
		shift
		;;
	*) usage ;;
	esac
done

work=$(git rev-parse --show-toplevel 2>/dev/null) || {
	echo "t4l-size: not inside a git repository" >&2
	exit 2
}
gc=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
case $gc in
*/.git) main=$(dirname "$gc") ;;
*) main=$work ;;
esac

if [ -z "$budget" ]; then
	budget=400
	if [ -f "$main/.t4l/config" ]; then
		_b=$(sed -n 's/^slice_budget=//p' "$main/.t4l/config" | head -n 1)
		[ -n "$_b" ] && budget=$_b
	fi
fi
case $budget in '' | *[!0-9]*) usage ;; esac

git -C "$work" rev-parse --verify --quiet "$base^{commit}" >/dev/null || {
	echo "t4l-size: unknown base ref '$base'" >&2
	exit 2
}

skip() {
	case $1 in
	*.lock | go.sum | */go.sum | package-lock.json | */package-lock.json | pnpm-lock.yaml | */pnpm-lock.yaml | bun.lockb | */bun.lockb) return 0 ;;
	*.min.js | *.min.css | *.pb.go | *_generated.* | *.gen.go) return 0 ;;
	vendor/* | node_modules/* | dist/* | .t4l/* | .claude/*) return 0 ;;
	esac
	return 1
}

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

git -C "$work" diff --numstat --no-renames "$base" -- . | while read -r add del f; do
	case $add in '-' | '') continue ;; esac
	skip "$f" && continue
	echo "$((add + del)) $f"
done >"$tmp"

git -C "$work" ls-files --others --exclude-standard | while IFS= read -r f; do
	skip "$f" && continue
	n=$(grep -c '' "$work/$f" 2>/dev/null || echo 0)
	echo "$n $f"
done >>"$tmp"

total=$(awk '{ s += $1 } END { print s + 0 }' "$tmp")

if [ "$quiet" -eq 1 ]; then
	echo "$total"
else
	pct=$((total * 100 / budget))
	echo "size: $total lines against $base (budget $budget, $pct%)"
	if [ "$files" -eq 1 ]; then
		sort -rn "$tmp" | head -n 10 | sed 's/^/  /'
	fi
fi
[ "$total" -le "$budget" ]
