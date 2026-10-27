#!/bin/sh
# Mutation testing on the code changed since a base ref. A mutant that survives
# is a change in behavior that no test notices. Optional, enabled per repository.
#
# Usage: t4l-mutate.sh [--base REF] [--threshold N] [--force]
#   --base REF      previous code: only lines changed since REF are mutated (default: HEAD)
#   --threshold N   minimum score in percent (default: mutation_threshold, else 80)
#   --force         run with gremlins even if .t4l/config does not enable mutation
#
# .t4l/config:
#   mutation=gremlins     Go, with gremlins
#                         (go install github.com/go-gremlins/gremlins/cmd/gremlins@v0.6.0)
#   mutation=<command>    any other tool (Stryker for TypeScript...), run as is from the
#                         repository root; its exit status is the verdict
#   mutation_threshold=80
#   mutation_timeout=900
# Score = killed / (killed + lived + not covered): changed code that no test runs
# counts against it. Committed, uncommitted and untracked changes are mutated, on
# a snapshot in a temporary worktree; the repository is not touched.
# Exit status: 0 score at or above the threshold, or mutation off; 1 below it;
# 2 usage or setup error.

set -u

base=HEAD
threshold=""
force=0
gremlins=${T4L_GREMLINS:-gremlins}

usage() {
	sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 2
}

die() {
	echo "t4l-mutate: $*" >&2
	exit 2
}

while [ $# -gt 0 ]; do
	case $1 in
	--base)
		[ $# -ge 2 ] || usage
		base=$2
		shift 2
		;;
	--threshold)
		[ $# -ge 2 ] || usage
		threshold=$2
		shift 2
		;;
	--force)
		force=1
		shift
		;;
	*) usage ;;
	esac
done

work=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
gc=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
case $gc in
*/.git) main=$(dirname "$gc") ;;
*) main=$work ;;
esac
cfg="$main/.t4l/config"
prefix=$(git rev-parse --show-prefix)

cfg_get() { # key default
	_v=""
	[ -f "$cfg" ] && _v=$(sed -n "s/^$1=//p" "$cfg" | head -n 1)
	printf '%s' "${_v:-$2}"
}

tool=$(cfg_get mutation "")
if [ -z "$tool" ]; then
	[ "$force" -eq 1 ] || {
		echo "mutation: off (enable it with mutation=gremlins in .t4l/config, or run with --force)"
		exit 0
	}
	tool=gremlins
fi
[ -n "$threshold" ] || threshold=$(cfg_get mutation_threshold 80)
case $threshold in '' | *[!0-9]*) die "threshold must be a whole percent" ;; esac
tmo=$(cfg_get mutation_timeout 900)
case $tmo in '' | *[!0-9]*) tmo=900 ;; esac
to=""
command -v timeout >/dev/null 2>&1 && to="timeout $tmo"

# any other tool: a command from the config, with the same trust rule as the hooks
if [ "$tool" != gremlins ]; then
	if [ "${T4L_TRUST_CONFIG:-}" != 1 ] && git -C "$main" ls-files --error-unmatch .t4l/config >/dev/null 2>&1; then
		die ".t4l/config is tracked by git, so its mutation command will not run (set T4L_TRUST_CONFIG=1 to allow it)"
	fi
	echo "mutation: $tool"
	# shellcheck disable=SC2086  # to is empty or two words
	out=$(cd "$work" && $to sh -c "$tool" 2>&1)
	rc=$?
	printf '%s\n' "$out" | tail -n 40
	if [ "$rc" -eq 0 ]; then
		echo "mutation: passed"
		exit 0
	fi
	echo "mutation: failed (exit $rc)"
	exit 1
fi

command -v "$gremlins" >/dev/null 2>&1 || die "gremlins not found (go install github.com/go-gremlins/gremlins/cmd/gremlins@v0.6.0)"
command -v jq >/dev/null 2>&1 || die "jq is required"
[ -f "$work/${prefix}go.mod" ] || die "run it from the directory of a Go module (no go.mod here)"
# gremlins accepts an unknown ref and reports nothing, so check it first
base_sha=$(git rev-parse --verify --quiet "$base^{commit}") || die "unknown base ref: $base"

tmp=$(mktemp -d)
snap_dir="$tmp/snap"
# shellcheck disable=SC2329  # called by the trap
cleanup() {
	git -C "$work" worktree remove --force "$snap_dir" >/dev/null 2>&1
	rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

# snapshot of the working tree, untracked files included, through a private index
idx="$tmp/index"
cp "$(git rev-parse --git-dir)/index" "$idx" 2>/dev/null
(cd "$work" && GIT_INDEX_FILE=$idx git add -A) || die "cannot snapshot the working tree"
tree=$(cd "$work" && GIT_INDEX_FILE=$idx git write-tree) || die "cannot snapshot the working tree"
snap=$(GIT_AUTHOR_NAME=t4l GIT_AUTHOR_EMAIL=t4l@localhost GIT_COMMITTER_NAME=t4l GIT_COMMITTER_EMAIL=t4l@localhost \
	git commit-tree "$tree" -p HEAD -m "t4l-mutate snapshot") || die "cannot snapshot the working tree"
git -C "$work" worktree add --detach -q "$snap_dir" "$snap" || die "cannot create the snapshot worktree"

echo "mutation: gremlins on lines changed since $base (threshold $threshold%)"
# shellcheck disable=SC2086
log=$(cd "$snap_dir/$prefix" && $to "$gremlins" unleash --diff "$base_sha" -o "$tmp/result.json" . 2>&1)
rc=$?
if [ ! -s "$tmp/result.json" ]; then
	printf '%s\n' "$log" | tail -n 20
	die "gremlins produced no result (exit $rc)"
fi

count() { jq "[.files[]?.mutations[]? | select(.status == \"$1\")] | length" "$tmp/result.json"; }
killed=$(count KILLED)
timed=$(count "TIMED OUT")
lived=$(count LIVED)
uncovered=$(count "NOT COVERED")
killed=$((killed + timed))
total=$((killed + lived + uncovered))

if [ "$total" -eq 0 ]; then
	echo "mutation: no mutants in the changed code"
	exit 0
fi

# survivors, with the source line, so a reader can tell a missing test from an equivalent mutant
jq -r '.files[]? | .file_name as $f | .mutations[]? | select(.status == "LIVED" or .status == "NOT COVERED") |
	"\(.status)\t\($f)\t\(.line)\t\(.type)"' "$tmp/result.json" |
	while IFS='	' read -r _st _f _l _t; do
		_src=$(sed -n "${_l}p" "$snap_dir/$prefix$_f" 2>/dev/null | sed 's/^[[:space:]]*//')
		printf '%-11s %s:%s  %s  | %s\n' "$_st" "$prefix$_f" "$_l" "$_t" "$_src"
	done

score=$((100 * killed / total))
echo "mutation: killed $killed, lived $lived, not covered $uncovered; score $score% (threshold $threshold%)"
if [ "$score" -ge "$threshold" ]; then
	exit 0
fi
echo "mutation: below the threshold. Each LIVED line needs a test that fails when that code changes; each NOT COVERED line needs a test that runs it. An equivalent mutant (no observable change) is noted, not tested."
exit 1
