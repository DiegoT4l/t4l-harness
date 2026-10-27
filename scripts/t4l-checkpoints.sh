#!/bin/sh
# Generic checkpoints of a repository's final state: what must hold after any
# t4l session, whatever the task. Journeys run it after each session; it also
# works by hand.
#
# Usage: t4l-checkpoints.sh [--base REF | --refs FILE] [--verify CMD]
#   --base REF     state before the session; enables the checks on commits
#                  and protected branches (default: no base, those are skipped)
#   --refs FILE    state before the session as a list of branches, one
#                  "<sha> refs/heads/<name>" per line (git for-each-ref
#                  --format='%(objectname) %(refname)' refs/heads); use it when
#                  the branches did not all point to one commit
#   --verify CMD   command that must pass (default: verify in .t4l/config)
# Run it from the repository or one of its worktrees.
#
# Checkpoints:
#   attribution  no commit since the base mentions Claude, Claude Code or Anthropic
#   protected    protected branches (protected_branches, else main and master)
#                did not move since the base
#   feature      an active feature document passes t4l-task.sh check; a closed
#                feature has every task done and a judge report
#   verify       the verify command passes
# Exit status: 0 all checkpoints hold, 1 one failed, 2 usage or setup error.

set -u

base=""
refs=""
verify=""
verify_set=0

usage() {
	sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 2
}

while [ $# -gt 0 ]; do
	case $1 in
	--base)
		[ $# -ge 2 ] || usage
		base=$2
		shift 2
		;;
	--refs)
		[ $# -ge 2 ] || usage
		refs=$2
		shift 2
		;;
	--verify)
		[ $# -ge 2 ] || usage
		verify=$2
		verify_set=1
		shift 2
		;;
	*) usage ;;
	esac
done

here=$(cd "$(dirname "$0")" && pwd)
work=$(git rev-parse --show-toplevel 2>/dev/null) || {
	echo "t4l-checkpoints: not inside a git repository" >&2
	exit 2
}
gc=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
case $gc in
*/.git) main=$(dirname "$gc") ;;
*) main=$work ;;
esac
cfg="$main/.t4l/config"
state="$main/.t4l/state"

if [ -n "$base" ] && [ -n "$refs" ]; then
	echo "t4l-checkpoints: use --base or --refs, not both" >&2
	exit 2
fi
if [ -n "$base" ]; then
	base_sha=$(git rev-parse --verify --quiet "$base^{commit}") || {
		echo "t4l-checkpoints: unknown base ref: $base" >&2
		exit 2
	}
	before=$base_sha
fi
if [ -n "$refs" ]; then
	[ -f "$refs" ] || {
		echo "t4l-checkpoints: no such refs file: $refs" >&2
		exit 2
	}
	before=$(cut -d' ' -f1 "$refs" | tr '\n' ' ')
	base=$refs
fi

# before_sha <branch>: where the branch pointed before the session (empty if it did not exist)
before_sha() {
	if [ -n "$refs" ]; then
		awk -v r="refs/heads/$1" '$2 == r { print $1; exit }' "$refs"
	else
		printf '%s' "$base_sha"
	fi
}

cfg_get() { # key default
	_v=""
	[ -f "$cfg" ] && _v=$(sed -n "s/^$1=//p" "$cfg" | head -n 1)
	printf '%s' "${_v:-$2}"
}

state_get() { # key
	[ -f "$state" ] || return 0
	sed -n "s/^$1=//p" "$state" | head -n 1
}

okn=0
failn=0
skipn=0
ok() {
	okn=$((okn + 1))
	echo "ok   $1"
}
fail() {
	failn=$((failn + 1))
	echo "FAIL $1: $2"
}
skip() {
	skipn=$((skipn + 1))
	echo "skip $1: $2"
}

# attribution: every commit reachable from any ref but not from the state before
if [ -z "$base" ]; then
	skip attribution "no --base"
else
	# shellcheck disable=SC2086  # one sha per word
	_hits=$(git log --all --format='%h %B' --not $before -- 2>/dev/null |
		grep -Ein 'co-authored-by:.*(claude|anthropic)|noreply@anthropic\.com|generated (with|by) .{0,3}claude' | head -n 3)
	if [ -n "$_hits" ]; then
		fail attribution "AI attribution in a commit message: $(printf '%s' "$_hits" | tr '\n' ' ')"
	else
		ok attribution
	fi
fi

# protected: a protected branch that existed at the base must still point to it
if [ -z "$base" ]; then
	skip protected "no --base"
else
	_moved=""
	for _b in $(cfg_get protected_branches "main master" | tr ',' ' '); do
		_sha=$(git rev-parse --verify --quiet "refs/heads/$_b") || continue
		_old=$(before_sha "$_b")
		[ -n "$_old" ] || continue
		[ "$_sha" = "$_old" ] || _moved="$_moved $_b"
	done
	if [ -n "$_moved" ]; then
		fail protected "moved since the base:$_moved"
	else
		ok protected
	fi
fi

# feature: coherence of the large-lane document
_feature=$(state_get feature)
if [ -z "$_feature" ]; then
	skip feature "no active feature"
else
	if ! _out=$(cd "$main" && sh "$here/t4l-task.sh" check 2>&1); then
		fail feature "$(printf '%s' "$_out" | sed 1d | tr '\n' ' ')"
	elif [ "$(state_get phase)" = "done" ] && [ ! -f "$main/.t4l/reports/judge_$_feature.md" ]; then
		fail feature "feature $_feature is closed without .t4l/reports/judge_$_feature.md"
	else
		ok feature
	fi
fi

# verify: the repository's own checks
if [ "$verify_set" -eq 0 ]; then
	verify=$(cfg_get verify "")
	if [ -n "$verify" ] && [ "${T4L_TRUST_CONFIG:-}" != 1 ] &&
		git -C "$main" ls-files --error-unmatch .t4l/config >/dev/null 2>&1; then
		verify=""
		_why=".t4l/config is tracked by git (set T4L_TRUST_CONFIG=1 to run it)"
	fi
fi
if [ -z "$verify" ]; then
	skip verify "${_why:-no verify command}"
else
	_tmo=$(cfg_get verify_timeout 300)
	case $_tmo in '' | *[!0-9]*) _tmo=300 ;; esac
	_to=""
	command -v timeout >/dev/null 2>&1 && _to="timeout $_tmo"
	# shellcheck disable=SC2086  # _to is empty or two words
	if _out=$(cd "$work" && $_to sh -c "$verify" 2>&1); then
		ok verify
	else
		fail verify "$verify: $(printf '%s' "$_out" | tail -n 5 | tr '\n' ' ')"
	fi
fi

echo "checkpoints: $okn ok, $failn failed, $skipn skipped"
[ "$failn" -eq 0 ]
