#!/bin/sh
# Integrate the task branches of the active feature on a separate branch and
# check the merged result. Nothing touches main or a remote.
#
# It creates the worktree .t4l/worktrees/integration on the branch
# t4l/<feature>/integration, snapshots any uncommitted work of each task on its
# own task branch, and merges the branches in dependency order (ties by ID).
# Then it runs the repo's verify command and, if given, the regression check on
# the merged tree, measures every task and proposes slices within the budget.
#
# Usage: t4l-integrate.sh [--base REF] [--verify CMD] [--regress-file FILE] [--abort]
#   --base REF           previous code (default: HEAD of the main checkout, remembered)
#   --verify CMD         verification command (default: verify= in .t4l/config)
#   --regress-file FILE  commands for t4l-regress.sh, run on the merged tree
#   --abort              remove the integration worktree and branch
# After a conflict, resolve it inside the integration worktree, commit, and run
# the same command again: branches already merged are skipped.
# Writes .t4l/reports/integrate_<feature>.md.
# Exit status: 0 integrated and verified, 1 verification or regression failed,
# 2 usage or setup error, 3 merge conflict.

set -u

here=$(cd "$(dirname "$0")" && pwd)
base=""
verify_cmd=""
regress=""
abort=0

usage() {
	sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 2
}

die() {
	echo "t4l-integrate: $*" >&2
	exit 2
}

while [ $# -gt 0 ]; do
	case $1 in
	--base)
		[ $# -ge 2 ] || usage
		base=$2
		shift 2
		;;
	--verify)
		[ $# -ge 2 ] || usage
		verify_cmd=$2
		shift 2
		;;
	--regress-file)
		[ $# -ge 2 ] || usage
		regress=$2
		shift 2
		;;
	--abort)
		abort=1
		shift
		;;
	*) usage ;;
	esac
done

gc=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || die "not inside a git repository"
case $gc in
*/.git) main=$(dirname "$gc") ;;
*) main=$(git rev-parse --show-toplevel) ;;
esac
# the regression file is relative to where the caller is, not to the integration worktree
case $regress in
'' | /*) ;;
*) regress="$(pwd)/$regress" ;;
esac
[ -z "$regress" ] || [ -f "$regress" ] || die "regress file not found: $regress"
state="$main/.t4l/state"
[ -f "$state" ] || die "no active feature"
feature=$(sed -n 's/^feature=//p' "$state" | head -n 1)
[ -n "$feature" ] || die "no active feature"

int="$main/.t4l/worktrees/integration"
ibranch="t4l/$feature/integration"
ienv="$main/.t4l/board/integration.env"

cfg_get() { # key default
	_v=""
	[ -f "$main/.t4l/config" ] && _v=$(sed -n "s/^$1=//p" "$main/.t4l/config" | head -n 1)
	printf '%s' "${_v:-$2}"
}

if [ "$abort" -eq 1 ]; then
	git -C "$main" worktree remove --force "$int" >/dev/null 2>&1
	git -C "$main" branch -D "$ibranch" >/dev/null 2>&1
	rm -f "$ienv"
	echo "integration removed"
	exit 0
fi

# --- tasks that have a registered branch ---------------------------------------
status_out=$(cd "$main" && sh "$here/t4l-task.sh" status 2>&1) || die "cannot read the task status: $status_out"
ids=""
for f in "$main"/.t4l/board/T[0-9]*.env; do
	[ -f "$f" ] || continue
	ids="$ids $(sed -n 's/^task=//p' "$f")"
done
[ -n "$ids" ] || die "no task has been started; nothing to integrate"

env_get() { sed -n "s/^$2=//p" "$main/.t4l/board/$1.env" | head -n 1; }
st_of() { printf '%s\n' "$status_out" | grep "^  $1 " | awk '{print $2}'; }
deps_of() { printf '%s\n' "$status_out" | grep "^  $1 " | sed -n 's/.*deps=\([^ ]*\).*/\1/p'; }

for t in $ids; do
	case $(st_of "$t") in
	review | "done") ;;
	*) die "$t is '$(st_of "$t")'; every task must be in review or done before integrating" ;;
	esac
	[ "$(env_get "$t" worktree)" = "$main" ] && die "$t was started in the main checkout; there is no task branch to integrate"
done

# --- dependency order -----------------------------------------------------------
order=""
left=$ids
while [ -n "$left" ]; do
	progressed=0
	rest=""
	for t in $left; do
		ready=1
		for d in $(deps_of "$t" | tr ',' ' '); do
			[ "$d" = "-" ] && continue
			case " $ids " in *" $d "*) case " $order " in *" $d "*) ;; *) ready=0 ;; esac ;; esac
		done
		if [ "$ready" -eq 1 ]; then
			order="$order $t"
			progressed=1
		else
			rest="$rest $t"
		fi
	done
	[ "$progressed" -eq 1 ] || die "dependency cycle among:$rest"
	left=$rest
done

# --- integration worktree --------------------------------------------------------
if [ ! -d "$int" ]; then
	[ -n "$base" ] || base=$(git -C "$main" rev-parse HEAD)
	git -C "$main" worktree add -q -b "$ibranch" "$int" "$base" || die "cannot create the integration worktree"
	mkdir -p "$main/.t4l/board"
	printf 'base=%s\n' "$base" >"$ienv"
else
	[ -n "$base" ] || base=$(sed -n 's/^base=//p' "$ienv" 2>/dev/null | head -n 1)
	[ -n "$base" ] || base=$(git -C "$main" rev-parse HEAD)
fi

# --- snapshot uncommitted work on the task branches, then merge -----------------------
for t in $order; do
	wt=$(env_get "$t" worktree)
	br=$(env_get "$t" branch)
	[ -d "$wt" ] || die "$t: worktree $wt no longer exists"
	if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
		if ! { git -C "$wt" add -A && git -C "$wt" commit -q -m "wip($t): snapshot for integration"; }; then
			die "$t: cannot snapshot the worktree (is git user.name/user.email set?)"
		fi
	fi
	if git -C "$int" merge-base --is-ancestor "$br" HEAD 2>/dev/null; then
		continue
	fi
	if ! git -C "$int" merge --no-ff -q -m "merge $t into the integration of $feature" "$br" >/dev/null 2>&1; then
		conflicts=$(git -C "$int" diff --name-only --diff-filter=U)
		if [ -n "$conflicts" ]; then
			echo "CONFLICT merging $t ($br) into $ibranch. Conflicted files:"
			printf '%s\n' "$conflicts" | sed 's/^/  /'
			echo "Resolve them in $int, commit, and run this command again."
			exit 3
		fi
		die "merge of $t failed without conflicts (is git user.name/user.email set?)"
	fi
done

# --- verification ---------------------------------------------------------------------
[ -n "$verify_cmd" ] || verify_cmd=$(cfg_get verify "")
verify_rc=0
verify_out=""
if [ -n "$verify_cmd" ]; then
	verify_out=$(cd "$int" && sh -c "$verify_cmd" 2>&1)
	verify_rc=$?
fi

regress_rc=0
regress_out=""
if [ -n "$regress" ]; then
	regress_out=$(cd "$int" && sh "$here/t4l-regress.sh" --base "$base" --file "$regress" 2>&1)
	regress_rc=$?
fi

# --- sizes and slice proposal -------------------------------------------------------------
budget=$(cfg_get slice_budget 400)
total=$(cd "$int" && sh "$here/t4l-size.sh" --base "$base" --budget "$budget" --quiet 2>/dev/null)
sizes=""
slices=""
cur=0
n=1
cur_ids=""
for t in $order; do
	# each task is measured from its own start, so work merged from its dependencies is not counted twice
	tbase=$(env_get "$t" base)
	s=$(cd "$(env_get "$t" worktree)" && sh "$here/t4l-size.sh" --base "${tbase:-$base}" --budget "$budget" --quiet 2>/dev/null)
	case $s in '' | *[!0-9]*) s=0 ;; esac
	sizes="$sizes
- $t: $s lines"
	if [ "$cur" -gt 0 ] && [ $((cur + s)) -gt "$budget" ]; then
		slices="$slices
- slice $n: $cur_ids ($cur lines)"
		n=$((n + 1))
		cur=0
		cur_ids=""
	fi
	cur=$((cur + s))
	cur_ids="${cur_ids:+$cur_ids, }$t"
done
slices="$slices
- slice $n: $cur_ids ($cur lines)"

# --- report ---------------------------------------------------------------------------------
mkdir -p "$main/.t4l/reports"
report="$main/.t4l/reports/integrate_$feature.md"
{
	echo "# Integration: $feature"
	echo
	echo "Branch: $ibranch ($int)"
	echo "Base: $base"
	echo "Merge order:$order"
	echo
	echo "## Size (budget $budget per slice)"
	echo "Integrated total: ${total:-0} lines"
	echo "$sizes"
	echo
	echo "Proposed slices, in merge order:$slices"
	echo
	echo "## Verification"
	if [ -n "$verify_cmd" ]; then
		echo '```'
		echo "\$ $verify_cmd (exit $verify_rc)"
		printf '%s\n' "$verify_out" | tail -n 25
		echo '```'
	else
		echo "No verify command configured."
	fi
	if [ -n "$regress" ]; then
		echo
		echo "## Regression on the merged tree"
		echo '```'
		printf '%s\n' "$regress_out" | tail -n 40
		echo '```'
	fi
} >"$report"

echo "integrated:$order -> $ibranch"
echo "size: ${total:-0} lines (budget $budget)"
echo "slices:$slices"
[ -n "$verify_cmd" ] && echo "verify: exit $verify_rc"
[ -n "$regress" ] && echo "regress: exit $regress_rc"
echo "report: $report"
[ "$verify_rc" -eq 0 ] && [ "$regress_rc" -eq 0 ]
