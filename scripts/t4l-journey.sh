#!/bin/sh
# Run journeys: reproducible headless sessions of Claude Code with this plugin on
# a throwaway copy of a fixture repository, judged by deterministic checkpoints.
# Use them to compare two versions of the harness. Each run spends real tokens.
#
# Usage:
#   t4l-journey.sh [options] <journey>...   run journeys (name in journeys/ or a path)
#   t4l-journey.sh [options] --all          run every journey
#   t4l-journey.sh --list                   list the journeys
#   t4l-journey.sh --compare DIR_A DIR_B    compare two result directories
#
#   --plugin-dir DIR   harness under test (default: this checkout)
#   --model M          model for the sessions (default: the CLI default)
#   --repeat N         run each journey N times (default: 1)
#   --budget USD       spend limit per session (default: 3)
#   --timeout SEC      limit per session (default: 1200)
#   --settings JSON    extra settings for the sessions (default: Engram disabled,
#                      so measurement runs do not write to your memory)
#   --out DIR          results (default: .t4l/journeys/<time>-<rev> in this checkout)
#   --keep             keep the work copies
# A journey's setup() runs in the work copy and may put fake tools in $BIN, which
# comes first in the session's PATH; the session is judged from the state it left.
# Environment: T4L_CLAUDE is the claude binary (default: claude).
# Exit status: 0 every run passed, 1 a run failed, 2 usage or setup error.
# shellcheck disable=SC2329  # the checkpoint helpers are called from journey files

set -u

here=$(cd "$(dirname "$0")/.." && pwd)
jdir="$here/journeys"
plugin=$here
model=""
repeat=1
budget=3
tmo=1200
settings='{"enabledPlugins":{"engram@engram":false}}'
out=""
keep=0
all=0
claude=${T4L_CLAUDE:-claude}

usage() {
	sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 2
}

die() {
	echo "t4l-journey: $*" >&2
	exit 2
}

journey_desc() { # file: first comment line
	sed -n 's/^# \{0,1\}//p' "$1" | head -n 1
}

compare() { # dirA dirB
	[ -f "$1/summary.tsv" ] || die "no summary.tsv in $1"
	[ -f "$2/summary.tsv" ] || die "no summary.tsv in $2"
	echo "A: $1"
	echo "B: $2"
	awk -F'\t' '
		function rate(p, n) { return n ? sprintf("%d/%d", p, n) : "-" }
		FNR == 1 { next }
		FILENAME == ARGV[1] { k = $1; seen[k] = 1; an[k]++; ap[k] += ($3 == "pass"); ac[k] += $6; at[k] += $7; next }
		{ k = $1; seen[k] = 1; bn[k]++; bp[k] += ($3 == "pass"); bc[k] += $6; bt[k] += $7 }
		END {
			printf "%-22s %7s %7s %9s %9s %7s %7s\n", "journey", "pass A", "pass B", "cost A", "cost B", "turns A", "turns B"
			for (k in seen)
				printf "%-22s %7s %7s %9s %9s %7s %7s\n", k, rate(ap[k], an[k]), rate(bp[k], bn[k]),
					an[k] ? sprintf("%.2f", ac[k] / an[k]) : "-", bn[k] ? sprintf("%.2f", bc[k] / bn[k]) : "-",
					an[k] ? sprintf("%.0f", at[k] / an[k]) : "-", bn[k] ? sprintf("%.0f", bt[k] / bn[k]) : "-"
		}' "$1/summary.tsv" "$2/summary.tsv"
	exit 0
}

names=""
while [ $# -gt 0 ]; do
	case $1 in
	--plugin-dir | --model | --repeat | --budget | --timeout | --settings | --out)
		[ $# -ge 2 ] || usage
		case $1 in
		--plugin-dir) plugin=$(cd "$2" 2>/dev/null && pwd) || die "no such directory: $2" ;;
		--model) model=$2 ;;
		--repeat) repeat=$2 ;;
		--budget) budget=$2 ;;
		--timeout) tmo=$2 ;;
		--settings) settings=$2 ;;
		--out) out=$2 ;;
		esac
		shift 2
		;;
	--keep)
		keep=1
		shift
		;;
	--all)
		all=1
		shift
		;;
	--list)
		for _f in "$jdir"/*.journey; do
			[ -f "$_f" ] || continue
			printf '%-22s %s\n' "$(basename "$_f" .journey)" "$(journey_desc "$_f")"
		done
		exit 0
		;;
	--compare)
		[ $# -eq 3 ] || usage
		compare "$2" "$3"
		;;
	-*) usage ;;
	*)
		names="$names $1"
		shift
		;;
	esac
done

case $repeat in '' | *[!0-9]* | 0) die "--repeat needs a positive integer" ;; esac
case $tmo in '' | *[!0-9]*) die "--timeout needs seconds" ;; esac
command -v jq >/dev/null 2>&1 || die "jq is required"
command -v "$claude" >/dev/null 2>&1 || die "claude not found (set T4L_CLAUDE)"

files=""
if [ "$all" -eq 1 ]; then
	for _f in "$jdir"/*.journey; do [ -f "$_f" ] && files="$files $_f"; done
fi
for _n in $names; do
	if [ -f "$_n" ]; then
		files="$files $(cd "$(dirname "$_n")" && pwd)/$(basename "$_n")"
	elif [ -f "$jdir/$_n.journey" ]; then
		files="$files $jdir/$_n.journey"
	else
		die "no such journey: $_n (see --list)"
	fi
done
[ -n "$files" ] || usage

rev=$(git -C "$plugin" describe --always --dirty 2>/dev/null || echo norev)
[ -n "$out" ] || out="$here/.t4l/journeys/$(date +%Y%m%d-%H%M%S)-$rev"
mkdir -p "$out" || die "cannot create $out"
out=$(cd "$out" && pwd)
printf 'journey\trun\tresult\tok\tfailed\tcost_usd\tturns\tseconds\tdenials\n' >"$out/summary.tsv"
echo "plugin: $plugin ($rev)"
echo "results: $out"

# --- checkpoint helpers, called from a journey's checkpoints() in the work copy

cp_ok() { echo "ok   $*" >>"$R/checkpoints.txt"; }
cp_fail() { echo "FAIL $*" >>"$R/checkpoints.txt"; }
cp_result() { # status description...
	if [ "$1" -eq 0 ]; then
		shift
		cp_ok "$@"
	else
		shift
		cp_fail "$@"
	fi
}

# files changed against the fixture commit, untracked included, t4l and Claude dirs left out
changed_files() {
	{
		git diff --name-only "$BASE"
		git ls-files --others --exclude-standard
	} | grep -Ev '^\.(t4l|claude)/' | sort -u
}

reply_has() {
	grep -Eq -- "$1" "$R/replies.txt"
	cp_result $? "reply_has $1"
}
reply_lacks() {
	! grep -Eq -- "$1" "$R/replies.txt"
	cp_result $? "reply_lacks $1"
}
transcript_has() {
	grep -Eq -- "$1" "$R/transcript.txt"
	cp_result $? "transcript_has $1"
}
transcript_order() { # first second: the first match of both, in this order
	_a=$(grep -Enm1 -- "$1" "$R/transcript.txt" | cut -d: -f1)
	_b=$(grep -Enm1 -- "$2" "$R/transcript.txt" | cut -d: -f1)
	[ -n "$_a" ] && [ -n "$_b" ] && [ "$_a" -lt "$_b" ]
	cp_result $? "transcript_order $1 before $2"
}
tool_used() {
	grep -qx -- "$1" "$R/tools.txt"
	cp_result $? "tool_used $1"
}
tool_unused() {
	! grep -qx -- "$1" "$R/tools.txt"
	cp_result $? "tool_unused $1"
}
clean() {
	_c=$(changed_files)
	[ -z "$_c" ]
	cp_result $? "clean$( [ -n "$_c" ] && printf ' (changed: %s)' "$(echo "$_c" | tr '\n' ' ')")"
}
changed() { # glob: at least one changed file matches
	_hit=1
	for _p in $(changed_files); do
		# shellcheck disable=SC2254  # the glob is the pattern
		case $_p in $1) _hit=0 ;; esac
	done
	cp_result "$_hit" "changed $1"
}
only_changed() { # glob...: every changed file matches one of them
	_bad=""
	for _p in $(changed_files); do
		_m=0
		for _g in "$@"; do
			# shellcheck disable=SC2254
			case $_p in $_g) _m=1 ;; esac
		done
		[ "$_m" -eq 1 ] || _bad="$_bad $_p"
	done
	[ -z "$_bad" ]
	cp_result $? "only_changed $*$( [ -n "$_bad" ] && printf ' (also:%s)' "$_bad")"
}
exists() { # glob
	_g=$1
	# shellcheck disable=SC2086  # the argument is a glob
	set -- $1
	[ -e "$1" ]
	cp_result $? "exists $_g"
}
absent() { # glob
	_g=$1
	# shellcheck disable=SC2086
	set -- $1
	[ ! -e "$1" ]
	cp_result $? "absent $_g"
}
cmd() {
	_o=$(sh -c "$1" 2>&1)
	_rc=$?
	if [ "$_rc" -eq 0 ]; then
		cp_ok "cmd $1"
	else
		cp_fail "cmd $1 (exit $_rc: $(printf '%s' "$_o" | tail -n 3 | tr '\n' ' '))"
	fi
}
generic() {
	# the runner's own checkpoints, so an older plugin is judged by the same rules
	sh "$here/scripts/t4l-checkpoints.sh" --refs "$R/refs" >"$R/generic.txt" 2>&1
	_rc=$?
	sed -n -e 's/^ok   /ok   generic: /p' -e 's/^FAIL /FAIL generic: /p' "$R/generic.txt" >>"$R/checkpoints.txt"
	[ "$_rc" -le 1 ] || cp_fail "generic (setup error: $(tail -n 1 "$R/generic.txt"))"
}

# --- one run of one journey

run_journey() { # file run
	_file=$1
	_run=$2
	_name=$(basename "$_file" .journey)
	R="$out/$_name/run$_run"
	mkdir -p "$R"
	: >"$R/checkpoints.txt"

	# reset what the journey file may define
	fixture=slug
	turns=""
	allow=""
	unset -f setup checkpoints 2>/dev/null
	turn() {
		turns="$turns$(printf '%s' "$1" | base64 | tr -d '\n')
"
	}
	# shellcheck disable=SC1090  # journeys are part of the harness
	. "$_file"

	# a fixture name lives in journeys/fixtures; a path is relative to the journey file
	case $fixture in
	*/*) _fx="$(dirname "$_file")/$fixture" ;;
	*) _fx="$jdir/fixtures/$fixture" ;;
	esac
	[ -d "$_fx" ] || {
		echo "  $_name: no fixture $fixture" >&2
		return 1
	}
	W=$(mktemp -d "${TMPDIR:-/tmp}/t4l-journey-$_name.XXXXXX")
	cp -R "$_fx/." "$W/"
	(
		cd "$W" && git init -q -b main && git add -A &&
			GIT_AUTHOR_NAME=t4l GIT_AUTHOR_EMAIL=t4l@example.com GIT_COMMITTER_NAME=t4l GIT_COMMITTER_EMAIL=t4l@example.com \
				git commit -qm "fixture $fixture"
	) || return 1
	echo "$W" >"$R/workdir"

	# setup may build history (commits, branches) and put fake tools in $BIN,
	# which comes first in the session's PATH
	BIN="$R/bin"
	mkdir -p "$BIN"
	if command -v setup >/dev/null 2>&1; then
		(cd "$W" && setup) >"$R/setup.txt" 2>&1 || cp_fail "setup (see setup.txt)"
	fi
	# the session is judged against the state setup left
	BASE=$(git -C "$W" rev-parse HEAD)
	git -C "$W" for-each-ref --format='%(objectname) %(refname)' refs/heads >"$R/refs"

	# one tool per line: a rule may contain spaces
	_allowed="Read
Edit
Write
Glob
Grep
Agent
Skill
TodoWrite
Bash(go *)
Bash(gofmt *)
Bash(git *)
Bash(sh $plugin/scripts/*)
Bash(ls *)
Bash(cat *)
Bash(grep *)
Bash(head *)
Bash(tail *)
Bash(diff *)
Bash(mkdir *)
Bash(printf *)
Bash(echo *)
Bash(sed *)
Bash(awk *)
Bash(find *)
Bash(wc *)
Bash(sort *)
$allow"
	_sid=""
	_i=0
	_t0=$(date +%s)
	for _b64 in $turns; do
		_i=$((_i + 1))
		_prompt=$(printf '%s' "$_b64" | base64 -d)
		# the prompt goes on stdin: --allowedTools takes every word that follows it
		set -- -p --plugin-dir "$plugin" --output-format stream-json --verbose \
			--permission-mode acceptEdits --max-budget-usd "$budget" --settings "$settings"
		[ -n "$model" ] && set -- "$@" --model "$model"
		[ -n "$_sid" ] && set -- "$@" --resume "$_sid"
		set -- "$@" --allowedTools
		_ifs=$IFS
		IFS='
'
		for _a in $_allowed; do [ -n "$_a" ] && set -- "$@" "$_a"; done
		IFS=$_ifs
		if command -v timeout >/dev/null 2>&1; then
			(cd "$W" && printf '%s' "$_prompt" | PATH="$BIN:$PATH" timeout "$tmo" "$claude" "$@") >"$R/turn$_i.jsonl" 2>"$R/turn$_i.err"
		else
			(cd "$W" && printf '%s' "$_prompt" | PATH="$BIN:$PATH" "$claude" "$@") >"$R/turn$_i.jsonl" 2>"$R/turn$_i.err"
		fi
		_rc=$?
		[ -n "$_sid" ] || _sid=$(jq -r 'select(.type=="system" and .subtype=="init") | .session_id' "$R/turn$_i.jsonl" 2>/dev/null | head -n 1)
		if [ $_rc -ne 0 ] || ! jq -e 'select(.type=="result" and .is_error==false)' "$R/turn$_i.jsonl" >/dev/null 2>&1; then
			cp_fail "session turn $_i (exit $_rc; see turn$_i.err)"
			break
		fi
	done
	_secs=$(($(date +%s) - _t0))

	cat "$R"/turn*.jsonl 2>/dev/null >"$R/all.jsonl"
	# every text the agent wrote, not only the final result: the mode line comes first
	jq -r '(select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text),
		(select(.type=="result") | .result // empty)' "$R/all.jsonl" >"$R/replies.txt" 2>/dev/null
	jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | .name' "$R/all.jsonl" >"$R/tools.txt" 2>/dev/null
	jq -r '(select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | "\(.name) \(.input | tostring)"),
		(select(.type=="user") | .message.content[]? | select(.type=="tool_result") | .content | if type=="array" then map(.text // "") | join("\n") else tostring end)' \
		"$R/all.jsonl" >"$R/transcript.txt" 2>/dev/null
	_cost=$(jq -s '[.[] | select(.type=="result") | .total_cost_usd // 0] | add // 0' "$R/all.jsonl" 2>/dev/null)
	_nt=$(jq -s '[.[] | select(.type=="result") | .num_turns // 0] | add // 0' "$R/all.jsonl" 2>/dev/null)
	_den=$(jq -s '[.[] | select(.type=="result") | (.permission_denials // []) | length] | add // 0' "$R/all.jsonl" 2>/dev/null)
	jq -r 'select(.type=="result") | .permission_denials[]? | "\(.tool_name) \(.tool_input | tostring)"' "$R/all.jsonl" >"$R/denials.txt" 2>/dev/null

	if command -v checkpoints >/dev/null 2>&1; then
		(cd "$W" && checkpoints)
	else
		cp_fail "journey defines no checkpoints()"
	fi

	_okc=$(grep -c '^ok ' "$R/checkpoints.txt")
	_failc=$(grep -c '^FAIL' "$R/checkpoints.txt")
	_res=pass
	[ "$_failc" -eq 0 ] || _res=fail
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$_name" "$_run" "$_res" "$_okc" "$_failc" "${_cost:-0}" "${_nt:-0}" "$_secs" "${_den:-0}" >>"$out/summary.tsv"
	printf '  %-22s run %s  %s  (%s ok, %s failed, $%s, %ss, %s denials)\n' "$_name" "$_run" "$_res" "$_okc" "$_failc" "${_cost:-0}" "$_secs" "${_den:-0}"
	grep '^FAIL' "$R/checkpoints.txt" | sed 's/^/      /'

	if [ "$keep" -eq 1 ]; then
		echo "      kept: $W"
	else
		rm -rf "$W"
	fi
	[ "$_res" = pass ]
}

failed=0
for _f in $files; do
	_r=1
	while [ "$_r" -le "$repeat" ]; do
		run_journey "$_f" "$_r" || failed=1
		_r=$((_r + 1))
	done
done
echo "summary: $out/summary.tsv"
exit "$failed"
