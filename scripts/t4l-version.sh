#!/bin/sh
# Compare the installed t4l version with the latest release on main.
#
# Usage: t4l-version.sh [--notice | --refresh]
#   (no option)  check now: installed and latest version, auto-update state, and
#                how to update. Exit 0 up to date, 1 update available, 2 cannot check.
#   --notice     for the SessionStart hook: print one line when the cached latest
#                version is newer, and refresh a missing or day-old cache in the
#                background. Never waits on the network; always exits 0.
#   --refresh    fetch the latest version into the cache, silently.
# Environment:
#   T4L_UPDATE_CHECK=off  no notice and no background fetch
#   T4L_LATEST_URL        where the latest plugin.json lives (default: main on GitHub)
# The cache lives in CLAUDE_PLUGIN_DATA, or ~/.cache/t4l outside a plugin.

set -u

here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
url=${T4L_LATEST_URL:-https://raw.githubusercontent.com/DiegoT4l/t4l-harness/main/.claude-plugin/plugin.json}
cache_dir=${CLAUDE_PLUGIN_DATA:-${XDG_CACHE_HOME:-$HOME/.cache}/t4l}
cache="$cache_dir/latest-version"
max_age=86400

usage() {
	sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 2
}

# version_of: the "version" field of the plugin.json on stdin
version_of() {
	sed -n '/"version"[[:space:]]*:/{s/.*"version"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p;q;}'
}

installed_version() {
	version_of <"$root/.claude-plugin/plugin.json" 2>/dev/null
}

fetch_latest() {
	command -v curl >/dev/null 2>&1 || return 1
	_v=$(curl -fsSL --max-time 5 "$url" 2>/dev/null | version_of)
	[ -n "$_v" ] || return 1
	printf '%s' "$_v"
}

# newer A B: true when version A is greater than version B
newer() {
	_a=$1
	_b=$2
	while [ -n "$_a$_b" ]; do
		_x=${_a%%.*}
		_y=${_b%%.*}
		[ "${_x:-0}" -gt "${_y:-0}" ] && return 0
		[ "${_x:-0}" -lt "${_y:-0}" ] && return 1
		case $_a in *.*) _a=${_a#*.} ;; *) _a="" ;; esac
		case $_b in *.*) _b=${_b#*.} ;; *) _b="" ;; esac
	done
	return 1
}

refresh() {
	_v=$(fetch_latest) || return 1
	mkdir -p "$cache_dir" 2>/dev/null || return 1
	printf '%s %s\n' "$(date +%s)" "$_v" >"$cache.$$" && mv "$cache.$$" "$cache"
}

# auto_update: on, off or unknown, following Claude Code's order: autoUpdate on the
# marketplace's extraKnownMarketplaces entry in a settings file, then the /plugin
# toggle in known_marketplaces.json, then off for a third-party marketplace.
auto_update() {
	if [ "${FORCE_AUTOUPDATE_PLUGINS:-}" != 1 ] &&
		[ -n "${DISABLE_UPDATES:-}${DISABLE_AUTOUPDATER:-}${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-}" ]; then
		echo "off (disabled by the environment)"
		return
	fi
	command -v jq >/dev/null 2>&1 || {
		echo "unknown (jq is not installed)"
		return
	}
	_cfg=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
	for _f in .claude/settings.local.json .claude/settings.json "$_cfg/settings.json"; do
		[ -f "$_f" ] || continue
		# not "// empty": it would turn an explicit false into "unset"
		_s=$(jq -r '.extraKnownMarketplaces["t4l-harness"].autoUpdate | if . == null then empty else tostring end' "$_f" 2>/dev/null)
		case $_s in
		true) echo on && return ;;
		false) echo off && return ;;
		esac
	done
	_k="${CLAUDE_CODE_PLUGIN_CACHE_DIR:-$_cfg/plugins}/known_marketplaces.json"
	if [ -f "$_k" ] && [ "$(jq -r '.["t4l-harness"].autoUpdate // false' "$_k" 2>/dev/null)" = true ]; then
		echo on
	else
		echo off
	fi
}

check_now() {
	cur=$(installed_version)
	[ -n "$cur" ] || {
		echo "t4l-version: no version in $root/.claude-plugin/plugin.json" >&2
		exit 2
	}
	au=$(auto_update)
	echo "installed: $cur"
	if ! lat=$(fetch_latest); then
		echo "latest: could not check ($url)"
		echo "auto-update: $au"
		exit 2
	fi
	refresh_cache_quietly "$lat"
	echo "latest: $lat"
	echo "auto-update: $au"
	if newer "$lat" "$cur"; then
		echo "update available: $cur -> $lat"
		case $au in
		on) echo "Claude Code installs it in the background; run /reload-plugins or restart to load it." ;;
		*) echo "Update with: claude plugin update t4l@t4l-harness (or /plugin, Marketplaces, t4l-harness, Enable auto-update)" ;;
		esac
		exit 1
	fi
	echo "up to date ($cur)"
}

refresh_cache_quietly() {
	mkdir -p "$cache_dir" 2>/dev/null &&
		printf '%s %s\n' "$(date +%s)" "$1" >"$cache.$$" 2>/dev/null &&
		mv "$cache.$$" "$cache" 2>/dev/null
	return 0
}

notice() {
	[ "${T4L_UPDATE_CHECK:-}" = off ] && exit 0
	# a checkout loaded with --plugin-dir is the development copy
	[ -e "$root/.git" ] && exit 0
	cur=$(installed_version)
	[ -n "$cur" ] || exit 0
	stamp=0
	lat=""
	if [ -f "$cache" ]; then
		read -r stamp lat <"$cache" || true
	fi
	now=$(date +%s)
	case $stamp in '' | *[!0-9]*) stamp=0 ;; esac
	if [ $((now - stamp)) -ge "$max_age" ]; then
		if command -v setsid >/dev/null 2>&1; then
			(setsid sh "$0" --refresh </dev/null >/dev/null 2>&1 &)
		else
			(sh "$0" --refresh </dev/null >/dev/null 2>&1 &)
		fi
	fi
	if [ -n "$lat" ] && newer "$lat" "$cur"; then
		echo "t4l $lat is available (this session runs $cur). Tell the user once: with auto-update on, Claude Code installs it in the background; otherwise run: claude plugin update t4l@t4l-harness"
	fi
	exit 0
}

case ${1:-} in
'') check_now ;;
--notice) notice ;;
--refresh)
	refresh
	exit 0
	;;
*) usage ;;
esac
