#!/bin/sh
# Compare existing entry points before and after a change.
#
# Runs every command from a list in two places: a clean checkout of a base ref
# (the previous code) and the current working tree. Compares stdout, stderr and
# exit code, and reports only the differences. A difference nobody asked for is a
# regression.
#
# Usage:
#   t4l-regress.sh [--base REF] [--timeout SEC] [--file FILE] < commands
#
#   --base REF      previous code to compare against (default: HEAD)
#   --timeout SEC   per-command limit, applied on both sides (default: 30)
#   --file FILE     read the commands from FILE instead of stdin
#
# One shell command per line; blank lines and lines starting with # are skipped.
# Commands run from the repository root. Put {edge} where a command takes free
# text: the line is run once per built-in edge input (empty, option-like such as
# -a- and --lead, unicode, padded, quoted), each passed as one quoted argument.
# Exit status: 0 no differences, 1 differences found, 2 usage or setup error.

set -u

base=HEAD
tmo=30
file=""

usage() {
	sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 2
}

while [ $# -gt 0 ]; do
	case $1 in
	--base)
		[ $# -ge 2 ] || usage
		base=$2
		shift 2
		;;
	--timeout)
		[ $# -ge 2 ] || usage
		tmo=$2
		shift 2
		;;
	--file)
		[ $# -ge 2 ] || usage
		file=$2
		shift 2
		;;
	-h | --help) usage ;;
	*) usage ;;
	esac
done

case $tmo in '' | *[!0-9]*) usage ;; esac

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
	echo "t4l-regress: not inside a git repository" >&2
	exit 2
}

tmp=$(mktemp -d) || exit 2
cleanup() {
	git -C "$root" worktree remove --force "$tmp/base" >/dev/null 2>&1
	git -C "$root" worktree prune >/dev/null 2>&1
	rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

if ! git -C "$root" worktree add --detach -q "$tmp/base" "$base" >/dev/null 2>&1; then
	echo "t4l-regress: cannot check out base ref '$base'" >&2
	exit 2
fi
# Ignored dependency directories do not exist in a clean checkout.
[ -d "$root/node_modules" ] && ln -s "$root/node_modules" "$tmp/base/node_modules"

if [ -n "$file" ]; then
	cat "$file" >"$tmp/cmds.raw" 2>/dev/null || {
		echo "t4l-regress: cannot read $file" >&2
		exit 2
	}
else
	cat >"$tmp/cmds.raw"
fi

# shquote <string>: the string as one single-quoted shell word.
shquote() {
	printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

: >"$tmp/cmds"
while IFS= read -r line || [ -n "$line" ]; do
	case $line in
	*"{edge}"*)
		prefix=${line%%"{edge}"*}
		suffix=${line#*"{edge}"}
		while IFS= read -r edge || [ -n "$edge" ]; do
			printf '%s%s%s\n' "$prefix" "$(shquote "$edge")" "$suffix" >>"$tmp/cmds"
		done <<'EDGES'

-a-
--lead
-
--
café
  padded  
a  b
日本
it's
EDGES
		;;
	*) printf '%s\n' "$line" >>"$tmp/cmds" ;;
	esac
done <"$tmp/cmds.raw"

esc() { printf '%s' "$1" | sed 's/[][\.*^$#]/\\&/g'; }
tmp_re=$(esc "$tmp/base")
root_re=$(esc "$root")
norm() {
	sed -e "s#$tmp_re#<root>#g" -e "s#$root_re#<root>#g" -e 's#[^ ]*/go-build[^ :]*#<go-build>#g' "$1"
}

run_in() { # dir tag command
	(
		cd "$1" || exit 1
		if command -v timeout >/dev/null 2>&1; then
			timeout "$tmo" sh -c "$3" </dev/null >"$tmp/$2.out" 2>"$tmp/$2.err"
		else
			sh -c "$3" </dev/null >"$tmp/$2.out" 2>"$tmp/$2.err"
		fi
		echo $? >"$tmp/$2.rc"
	)
	norm "$tmp/$2.out" >"$tmp/$2.out.n"
	norm "$tmp/$2.err" >"$tmp/$2.err.n"
}

total=0
differ=0
same=0
shown=0
max_show=15

while IFS= read -r cmd || [ -n "$cmd" ]; do
	case $cmd in '' | '#'*) continue ;; esac
	total=$((total + 1))
	run_in "$tmp/base" before "$cmd"
	run_in "$root" after "$cmd"

	changed=""
	cmp -s "$tmp/before.out.n" "$tmp/after.out.n" || changed="$changed stdout"
	cmp -s "$tmp/before.err.n" "$tmp/after.err.n" || changed="$changed stderr"
	cmp -s "$tmp/before.rc" "$tmp/after.rc" || changed="$changed exit-code"

	if [ -z "$changed" ]; then
		same=$((same + 1))
		continue
	fi
	differ=$((differ + 1))
	shown=$((shown + 1))
	if [ "$shown" -gt "$max_show" ]; then
		continue
	fi
	printf 'DIFF: %s\n  changed:%s\n' "$cmd" "$changed"
	printf '  exit code: %s -> %s\n' "$(cat "$tmp/before.rc")" "$(cat "$tmp/after.rc")"
	for s in out err; do
		if ! cmp -s "$tmp/before.$s.n" "$tmp/after.$s.n"; then
			label=stdout
			[ "$s" = err ] && label=stderr
			echo "  $label (before -> after):"
			diff -u --label before --label after "$tmp/before.$s.n" "$tmp/after.$s.n" | tail -n +3 | head -n 20 | sed 's/^/    /'
		fi
	done
done <"$tmp/cmds"

if [ "$total" -eq 0 ]; then
	echo "t4l-regress: no commands given" >&2
	exit 2
fi

[ "$shown" -gt "$max_show" ] && echo "(only the first $max_show differences are shown)"
echo "regress: $total compared against $base, $same same, $differ differ"
[ "$differ" -eq 0 ]
