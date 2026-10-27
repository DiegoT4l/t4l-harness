#!/bin/sh
# Manage the feature document and the machine state of the large lane.
#
# State lives in <repo>/.t4l/state (KEY=VALUE); the feature document is
# <repo>/.t4l/tasks/<feature>.md. The hook guard reads the state, so phases and
# gates are enforced, not just written down.
#
# Usage: t4l-task.sh <command> [args]
#   new <feature> [--mode odd|tdd|sdd] [--request TEXT]
#                              create the document and state (sdd starts at gate=pending)
#   approve                    specs approved by the user: gate=approved, phase=implementing
#   add <ID> <SPEC> [--deps T1,T2] [--files GLOB,GLOB]
#                              append a task (status todo); ID is T<number>, SPEC is S<number>
#   start <ID>                 todo -> doing (deps in review or done, WIP respected); records
#                              the worktree and branch of the caller in .t4l/board/<ID>.env
#   parallel on|off            parallel mode: WIP 2 by default, Files required, no overlap,
#                              subagents work in isolated worktrees
#   board                      kanban view: columns, WIP and owners
#   where                      absolute paths of the main checkout, state and reports
#   plan-check                 list undeclared Files and overlapping Files between tasks
#   review <ID>                doing -> review
#   done <ID> [SHA]            review|doing -> done; SHA is optional but must exist if given
#   reopen <ID> <REASON>       back to todo, reason appended to the log
#   log <TEXT>                 append a line to the log
#   status                     summary of state and tasks
#   check                      coherence checks; exit 1 and list problems
#   close                      all tasks done and check clean: phase=done
# Exit status: 0 ok, 1 refused or problems found, 2 usage error.

# Files globs are data: never expand them against the filesystem.
set -u -f

die() {
	echo "t4l-task: $*" >&2
	exit 1
}

usage() {
	sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 2
}

gc=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || die "not inside a git repository"
case $gc in
*/.git) root=$(dirname "$gc") ;;
*) root=$(git rev-parse --show-toplevel) ;;
esac
dir="$root/.t4l"
state="$dir/state"
cfg="$dir/config"

state_get() { # key
	[ -f "$state" ] || return 0
	sed -n "s/^$1=//p" "$state" | head -n 1
}

state_set() { # key value
	mkdir -p "$dir"
	_t=$(mktemp)
	if [ -f "$state" ]; then grep -v "^$1=" "$state" >"$_t"; fi
	printf '%s=%s\n' "$1" "$2" >>"$_t"
	cat "$_t" >"$state"
	rm -f "$_t"
}

cfg_get() { # key default
	_v=""
	[ -f "$cfg" ] && _v=$(sed -n "s/^$1=//p" "$cfg" | head -n 1)
	printf '%s' "${_v:-$2}"
}

need_active() {
	feature=$(state_get feature)
	[ -n "$feature" ] || die "no active feature (run: new <feature>)"
	doc="$dir/tasks/$feature.md"
	[ -f "$doc" ] || die "feature document missing: $doc"
	phase=$(state_get phase)
	gate=$(state_get gate)
	mode=$(state_get mode)
}

valid_id() { printf '%s' "$1" | grep -Eq '^T[0-9]+$'; }
valid_spec() { printf '%s' "$1" | grep -Eq '^S[0-9]+$'; }

task_ids() { awk -F'|' '/^\| *T[0-9]+ *\|/ { x=$2; gsub(/^[ \t]+|[ \t]+$/, "", x); print x }' "$doc"; }

task_exists() { task_ids | grep -qx "$1"; }

task_field() { # id column(1..6)
	awk -F'|' -v id="$1" -v n="$2" '/^\| *T[0-9]+ *\|/ {
		x=$2; gsub(/^[ \t]+|[ \t]+$/, "", x)
		if (x==id) { y=$(n+1); gsub(/^[ \t]+|[ \t]+$/, "", y); print y; exit }
	}' "$doc"
}

task_set() { # id column value
	_t=$(mktemp)
	TID="$1" COL="$2" VAL="$3" awk -F'|' 'BEGIN { OFS="|" }
		/^\| *T[0-9]+ *\|/ {
			x=$2; gsub(/^[ \t]+|[ \t]+$/, "", x)
			if (x==ENVIRON["TID"]) $(ENVIRON["COL"]+1) = " " ENVIRON["VAL"] " "
		}
		{ print }' "$doc" >"$_t" && cat "$_t" >"$doc"
	rm -f "$_t"
}

log_append() {
	_n=$(grep -o '^L[0-9][0-9]*\.' "$doc" | tr -dc '0-9\n' | sort -n | tail -n 1)
	printf 'L%s. %s\n' "$((${_n:-0} + 1))" "$1" >>"$doc"
}

spec_ids() { grep -o '^S[0-9][0-9]*\.' "$doc" | tr -d '.'; }

glob_prefix() { # static prefix of a glob, up to the first wildcard
	_gp_g=$1
	printf '%s' "${_gp_g%%[*?[]*}"
}

globs_overlap() { # "a,b" "c,d" -> 0 when any pair may overlap (conservative)
	# variables are prefixed _go_ because sh has no local scope
	for _go_a in $(printf '%s' "$1" | tr ',' ' '); do
		for _go_b in $(printf '%s' "$2" | tr ',' ' '); do
			_go_pa=$(glob_prefix "$_go_a")
			_go_pb=$(glob_prefix "$_go_b")
			case $_go_pa in "$_go_pb"*) return 0 ;; esac
			case $_go_pb in "$_go_pa"*) return 0 ;; esac
		done
	done
	return 1
}

parallel_on() { [ "$(state_get parallel)" = 1 ]; }

wip_limit() {
	if parallel_on; then cfg_get wip 2; else cfg_get wip 1; fi
}

board_file() { printf '%s/board/%s.env' "$dir" "$1"; }

task_ids_with() { # status
	for _t in $(task_ids); do
		[ "$(task_field "$_t" 3)" = "$1" ] && echo "$_t"
	done
}

cmd_new() {
	[ $# -ge 1 ] || usage
	_f=$1
	shift
	printf '%s' "$_f" | grep -Eq '^[a-z0-9][a-z0-9-]*$' || die "feature name must be lowercase letters, digits and hyphens"
	_mode=sdd
	_req=""
	while [ $# -gt 0 ]; do
		case $1 in
		--mode)
			[ $# -ge 2 ] || usage
			_mode=$2
			shift 2
			;;
		--request)
			[ $# -ge 2 ] || usage
			_req=$2
			shift 2
			;;
		*) usage ;;
		esac
	done
	case $_mode in odd | tdd | sdd) ;; *) die "mode must be odd, tdd or sdd" ;; esac
	_cur=$(state_get feature)
	_curphase=$(state_get phase)
	if [ -n "$_cur" ] && [ "$_curphase" != "done" ]; then
		die "feature '$_cur' is still active (phase=$_curphase); close it first"
	fi
	mkdir -p "$dir/tasks" "$dir/reports"
	_doc="$dir/tasks/$_f.md"
	[ -e "$_doc" ] && die "$_doc already exists"
	_label="ODD only"
	[ "$_mode" = tdd ] && _label="ODD + TDD"
	[ "$_mode" = sdd ] && _label="ODD + SDD"
	{
		printf '# %s\n\n' "$_f"
		printf 'Mode: %s   Lane: large\n\n' "$_label"
		printf '## Specs\n\n'
		printf 'S1. <behavior>. Quote the exact strings, error messages and examples verbatim.\n'
		printf '    Acceptance: <observable criterion>\n'
		printf '    Check: <command that proves it>\n'
		# shellcheck disable=SC2016  # the backticks are literal text in the template
		printf '    Existing behavior at risk: <inputs that work today and might change, or `none` and why>\n\n'
		printf '## Tasks\n\n'
		printf '| ID | Spec | Status | Deps | Files | Commit |\n'
		printf '|----|------|--------|------|-------|--------|\n\n'
		printf '## Log\n\n'
		printf 'L1. %s\n' "${_req:-<the user request, verbatim>}"
	} >"$_doc"
	state_set feature "$_f"
	state_set mode "$_mode"
	if [ "$_mode" = sdd ]; then
		state_set gate pending
		state_set phase specs
	else
		state_set gate none
		state_set phase implementing
	fi
	if ! { [ -f "$root/.gitignore" ] && grep -qx '\.t4l/' "$root/.gitignore"; }; then
		printf '.t4l/\n' >>"$root/.gitignore"
	fi
	echo "created $_doc (mode=$_mode, phase=$(state_get phase), gate=$(state_get gate))"
}

cmd_approve() {
	need_active
	[ "$gate" = pending ] || die "nothing to approve (gate=$gate)"
	spec_ids | grep -q . || die "the document has no specs (S1., S2., ...)"
	grep -q '<behavior>' "$doc" && die "S1 is still the template placeholder"
	grep -q 'Existing behavior at risk' "$doc" || die "specs must include 'Existing behavior at risk'"
	state_set gate approved
	state_set phase implementing
	log_append "specs approved by the user"
	echo "approved: phase=implementing"
}

cmd_add() {
	need_active
	[ $# -ge 2 ] || usage
	_id=$1
	_spec=$2
	shift 2
	valid_id "$_id" || die "task ID must look like T1"
	valid_spec "$_spec" || die "spec must look like S1"
	spec_ids | grep -qx "$_spec" || die "spec $_spec is not in the document"
	task_exists "$_id" && die "task $_id already exists"
	_deps="-"
	_files="-"
	while [ $# -gt 0 ]; do
		case $1 in
		--deps)
			[ $# -ge 2 ] || usage
			_deps=$2
			shift 2
			;;
		--files)
			[ $# -ge 2 ] || usage
			_files=$2
			shift 2
			;;
		*) usage ;;
		esac
	done
	_t=$(mktemp)
	# insert after the last table row (or the separator line when the table is empty)
	_last=$(grep -n '^|' "$doc" | tail -n 1 | cut -d: -f1)
	[ -n "$_last" ] || die "Tasks table not found in $doc"
	awk -v n="$_last" -v row="| $_id | $_spec | todo | $_deps | $_files | - |" '{ print } NR==n { print row }' "$doc" >"$_t" && cat "$_t" >"$doc"
	rm -f "$_t"
	echo "added $_id ($_spec)"
}

cmd_start() {
	need_active
	[ $# -ge 1 ] || usage
	_id=$1
	[ "$gate" = pending ] && die "specs are not approved yet (gate=pending)"
	[ "$phase" = implementing ] || die "phase is '$phase', expected implementing"
	task_exists "$_id" || die "unknown task $_id"
	[ "$(task_field "$_id" 3)" = todo ] || die "$_id is '$(task_field "$_id" 3)', expected todo"
	for _d in $(task_field "$_id" 4 | tr ',' ' '); do
		[ "$_d" = "-" ] && continue
		case $(task_field "$_d" 3) in
		review | "done") ;;
		*) die "$_id depends on $_d, which is '$(task_field "$_d" 3)'; it must be in review or done" ;;
		esac
	done
	_files=$(task_field "$_id" 5)
	_here=$(git rev-parse --show-toplevel 2>/dev/null)
	if parallel_on; then
		{ [ -n "$_files" ] && [ "$_files" != "-" ]; } || die "parallel mode: declare Files for $_id before starting it"
		[ "$_here" != "$root" ] || die "parallel mode: start $_id from inside your isolated worktree, not from the main checkout"
		for _o in $(task_ids_with doing); do
			if globs_overlap "$_files" "$(task_field "$_o" 5)"; then
				die "$_id overlaps with $_o, which is doing (Files $_files vs $(task_field "$_o" 5))"
			fi
		done
	fi
	_wip=$(wip_limit)
	_doing=$(task_ids_with doing | wc -l)
	[ "$_doing" -lt "$_wip" ] || die "WIP limit reached ($_doing doing, limit $_wip)"
	task_set "$_id" 3 doing
	mkdir -p "$dir/board"
	{
		printf 'task=%s\n' "$_id"
		printf 'worktree=%s\n' "$_here"
		printf 'branch=%s\n' "$(git branch --show-current 2>/dev/null)"
		printf 'base=%s\n' "$(git rev-parse HEAD 2>/dev/null)"
		printf 'files=%s\n' "$_files"
	} >"$(board_file "$_id")"
	echo "$_id: doing"
}

cmd_parallel() {
	need_active
	case ${1:-} in
	on)
		state_set parallel 1
		# local ignore, so the user's tracked .gitignore is not modified
		_ex="$gc/info/exclude"
		mkdir -p "$gc/info"
		if ! { [ -f "$_ex" ] && grep -qx '\.claude/worktrees/' "$_ex"; }; then
			printf '.claude/worktrees/\n' >>"$_ex"
		fi
		echo "parallel mode on (WIP limit $(wip_limit))"
		;;
	off)
		state_set parallel 0
		echo "parallel mode off (WIP limit $(wip_limit))"
		;;
	*) usage ;;
	esac
}

cmd_where() {
	echo "root=$root"
	echo "state=$state"
	echo "reports=$dir/reports"
	echo "tasks=$dir/tasks"
}

cmd_board() {
	need_active
	echo "feature=$feature phase=$phase parallel=$(state_get parallel | sed 's/^$/0/') WIP $(task_ids_with doing | wc -l)/$(wip_limit)"
	for _c in todo doing review "done"; do
		printf '%-7s' "$_c"
		for _t in $(task_ids_with "$_c"); do
			printf ' %s' "$_t"
			if [ "$_c" = doing ] || [ "$_c" = review ]; then
				_bf=$(board_file "$_t")
				[ -f "$_bf" ] && printf '[%s]' "$(sed -n 's/^branch=//p' "$_bf")"
			fi
			_dp=$(task_field "$_t" 4)
			[ "$_c" = todo ] && [ "$_dp" != "-" ] && printf '(after %s)' "$_dp"
		done
		echo
	done
}

cmd_plan_check() {
	need_active
	_problems=""
	_ids=$(task_ids)
	for _t in $_ids; do
		[ "$(task_field "$_t" 3)" = "done" ] && continue
		_f=$(task_field "$_t" 5)
		if [ -z "$_f" ] || [ "$_f" = "-" ]; then
			_problems="$_problems- $_t has no Files declared
"
		fi
	done
	# every unordered pair once
	# shellcheck disable=SC2086  # word splitting is intended
	set -- $_ids
	while [ $# -gt 0 ]; do
		_a=$1
		shift
		for _b in "$@"; do
			[ "$(task_field "$_a" 3)" = "done" ] && continue
			[ "$(task_field "$_b" 3)" = "done" ] && continue
			_fa=$(task_field "$_a" 5)
			_fb=$(task_field "$_b" 5)
			{ [ -n "$_fa" ] && [ "$_fa" != "-" ] && [ -n "$_fb" ] && [ "$_fb" != "-" ]; } || continue
			# tasks that depend directly on each other never run together
			case ",$(task_field "$_a" 4)," in *",$_b,"*) continue ;; esac
			case ",$(task_field "$_b" 4)," in *",$_a,"*) continue ;; esac
			if globs_overlap "$_fa" "$_fb"; then
				_problems="$_problems- $_a and $_b may overlap ($_fa vs $_fb); add a dependency or split the Files
"
			fi
		done
	done
	if [ -n "$_problems" ]; then
		printf 'plan-check: problems found\n%s' "$_problems"
		return 1
	fi
	echo "plan-check: ok (tasks can run in parallel where dependencies allow)"
}

cmd_review() {
	need_active
	[ $# -ge 1 ] || usage
	task_exists "$1" || die "unknown task $1"
	[ "$(task_field "$1" 3)" = doing ] || die "$1 is '$(task_field "$1" 3)', expected doing"
	task_set "$1" 3 review
	echo "$1: review"
}

cmd_done() {
	need_active
	[ $# -ge 1 ] || usage
	_id=$1
	_sha=${2:--}
	task_exists "$_id" || die "unknown task $_id"
	case $(task_field "$_id" 3) in doing | review) ;; *) die "$_id is '$(task_field "$_id" 3)', expected doing or review" ;; esac
	if [ "$_sha" != "-" ]; then
		_full=$(git -C "$root" rev-parse --verify --quiet "$_sha^{commit}") || die "commit $_sha not found"
		_sha=$(printf '%s' "$_full" | cut -c1-7)
	fi
	task_set "$_id" 3 "done"
	task_set "$_id" 6 "$_sha"
	echo "$_id: done ($_sha)"
}

cmd_reopen() {
	need_active
	[ $# -ge 2 ] || usage
	task_exists "$1" || die "unknown task $1"
	_id=$1
	shift
	task_set "$_id" 3 todo
	task_set "$_id" 6 "-"
	rm -f "$(board_file "$_id")"
	log_append "reopened $_id: $*"
	echo "$_id: todo (reopened)"
}

cmd_log() {
	need_active
	[ $# -ge 1 ] || usage
	log_append "$*"
}

cmd_status() {
	feature=$(state_get feature)
	if [ -z "$feature" ]; then
		echo "no active feature"
		return 0
	fi
	need_active
	echo "feature=$feature mode=$mode gate=$gate phase=$phase"
	for _id in $(task_ids); do
		printf '  %s  %-6s  spec=%s  deps=%s  files=%s  commit=%s\n' "$_id" "$(task_field "$_id" 3)" "$(task_field "$_id" 2)" "$(task_field "$_id" 4)" "$(task_field "$_id" 5)" "$(task_field "$_id" 6)"
	done
}

cmd_check() {
	need_active
	_problems=""
	add_problem() { _problems="$_problems- $1
"; }
	_wip=$(wip_limit)
	_doing=0
	for _id in $(task_ids); do
		_st=$(task_field "$_id" 3)
		case $_st in todo | doing | review | done) ;; *) add_problem "$_id has unknown status '$_st'" ;; esac
		[ "$_st" = doing ] && _doing=$((_doing + 1))
		_sp=$(task_field "$_id" 2)
		spec_ids | grep -qx "$_sp" || add_problem "$_id refers to missing spec $_sp"
		for _d in $(task_field "$_id" 4 | tr ',' ' '); do
			[ "$_d" = "-" ] && continue
			task_exists "$_d" || add_problem "$_id depends on missing task $_d"
		done
		if [ "$_st" = "done" ]; then
			_c=$(task_field "$_id" 6)
			if [ "$_c" = "-" ] && [ "$(cfg_get require_commit 0)" = 1 ]; then
				add_problem "$_id is done without a commit"
			elif [ "$_c" != "-" ] && ! git -C "$root" rev-parse --verify --quiet "$_c^{commit}" >/dev/null; then
				add_problem "$_id records commit $_c, which does not exist"
			fi
		fi
	done
	[ "$_doing" -le "$_wip" ] || add_problem "$_doing tasks are doing; WIP limit is $_wip"
	grep -q '^L1\. ' "$doc" || add_problem "log has no L1 (the original request)"
	grep -q '^L1\. <the user request' "$doc" && add_problem "L1 is still the template placeholder"
	if [ "$mode" = sdd ] && [ "$phase" != specs ] && [ "$gate" != approved ]; then
		add_problem "mode is sdd and phase is $phase, but the specs are not approved (gate=$gate)"
	fi
	if [ "$mode" = sdd ] && ! grep -q 'Existing behavior at risk' "$doc"; then
		add_problem "specs have no 'Existing behavior at risk' line"
	fi
	if [ -n "$_problems" ]; then
		printf 'check: problems found\n%s' "$_problems"
		return 1
	fi
	echo "check: ok"
}

cmd_close() {
	need_active
	cmd_check >/dev/null || {
		cmd_check
		return 1
	}
	for _id in $(task_ids); do
		[ "$(task_field "$_id" 3)" = "done" ] || die "$_id is not done"
	done
	state_set phase "done"
	log_append "feature closed"
	echo "closed: phase=done"
}

[ $# -ge 1 ] || usage
c=$1
shift
case $c in
new) cmd_new "$@" ;;
approve) cmd_approve "$@" ;;
add) cmd_add "$@" ;;
start) cmd_start "$@" ;;
review) cmd_review "$@" ;;
done) cmd_done "$@" ;;
reopen) cmd_reopen "$@" ;;
log) cmd_log "$@" ;;
status) cmd_status "$@" ;;
parallel) cmd_parallel "$@" ;;
board) cmd_board "$@" ;;
where) cmd_where "$@" ;;
plan-check) cmd_plan_check "$@" ;;
check) cmd_check "$@" ;;
close) cmd_close "$@" ;;
-h | --help | help) usage ;;
*) usage ;;
esac
