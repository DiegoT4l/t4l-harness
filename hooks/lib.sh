#!/bin/sh
# Shared helpers for t4l hooks. POSIX sh. Sourced, not executed.
# shellcheck disable=SC2034  # CFG_* variables are read by the sourcing hooks
#
# Hooks are opt-in per repository: nothing runs unless <repo>/.t4l/config exists.
# The config is parsed as KEY=VALUE lines and never sourced or eval'd.

CFG_QUICK=""
CFG_QUICK_EXT=""
CFG_QUICK_TIMEOUT=60
CFG_VERIFY=""
CFG_VERIFY_TIMEOUT=300
CFG_DISABLE=""
CFG_PROTECTED=""

t4l_read_input() {
	T4L_INPUT=$(cat)
}

# t4l_json <jq filter> <key for the sed fallback>
t4l_json() {
	if [ -z "${T4L_NO_JQ:-}" ] && command -v jq >/dev/null 2>&1; then
		printf '%s' "$T4L_INPUT" | jq -r "$1 // empty" 2>/dev/null
	else
		printf '%s' "$T4L_INPUT" | tr -d '\n' |
			sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
	fi
}

t4l_stop_hook_active() {
	printf '%s' "$T4L_INPUT" | tr -d '\n' |
		grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'
}

# t4l_repo_root <dir>: prints the git toplevel or fails.
t4l_repo_root() {
	git -C "$1" rev-parse --show-toplevel 2>/dev/null
}

# t4l_load_config <root>: returns 1 when hooks must stay inactive for this repo.
t4l_load_config() {
	_cfg="$1/.t4l/config"
	[ -f "$_cfg" ] || return 1
	if [ "${T4L_TRUST_CONFIG:-}" != 1 ] &&
		git -C "$1" ls-files --error-unmatch .t4l/config >/dev/null 2>&1; then
		echo "t4l: .t4l/config is tracked by git, so its commands will not run. Set T4L_TRUST_CONFIG=1 to allow it." >&2
		return 1
	fi
	while IFS= read -r _line || [ -n "$_line" ]; do
		case $_line in
		'' | '#'*) continue ;;
		esac
		_key=${_line%%=*}
		_val=${_line#*=}
		case $_key in
		quick) CFG_QUICK=$_val ;;
		quick_ext) CFG_QUICK_EXT=$_val ;;
		quick_timeout) CFG_QUICK_TIMEOUT=$_val ;;
		verify) CFG_VERIFY=$_val ;;
		verify_timeout) CFG_VERIFY_TIMEOUT=$_val ;;
		disable) CFG_DISABLE=$_val ;;
		protected_branches) CFG_PROTECTED=$_val ;;
		esac
	done <"$_cfg"
	case $CFG_QUICK_TIMEOUT in '' | *[!0-9]*) CFG_QUICK_TIMEOUT=60 ;; esac
	case $CFG_VERIFY_TIMEOUT in '' | *[!0-9]*) CFG_VERIFY_TIMEOUT=300 ;; esac
	[ "$CFG_DISABLE" != 1 ]
}

# t4l_run <dir> <timeout seconds> <command>: combined output on stdout.
t4l_run() {
	(
		cd "$1" || exit 1
		if command -v timeout >/dev/null 2>&1; then
			timeout "$2" sh -c "$3"
		else
			sh -c "$3"
		fi
	) 2>&1
}

# t4l_safe_path <path>: only plain path characters may reach a shell command.
t4l_safe_path() {
	case $1 in
	'' | *[!A-Za-z0-9._/@+-]*) return 1 ;;
	esac
	return 0
}
