#!/bin/sh
# Build the plugin archive from a git ref: only what the plugin needs at run
# time (manifest, kernel, skills, agents, hooks, scripts), never the tests,
# journeys or docs. Claude Code loads it with: claude --plugin-dir <zip>
#
# Usage: t4l-package.sh [--ref REF] [--out DIR] [--expect VERSION]
#   --ref REF          commit or tag to package (default: HEAD)
#   --out DIR          where to write the zip (default: dist)
#   --expect VERSION   fail unless .claude-plugin/plugin.json at REF has this version
# Prints the path of t4l-<version>.zip.
# Exit status: 0 built, 1 version mismatch, 2 usage or setup error.

set -u

ref=HEAD
out=dist
expect=""

usage() {
	sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 2
}

die() {
	echo "t4l-package: $*" >&2
	exit 2
}

while [ $# -gt 0 ]; do
	case $1 in
	--ref | --out | --expect)
		[ $# -ge 2 ] || usage
		case $1 in
		--ref) ref=$2 ;;
		--out) out=$2 ;;
		--expect) expect=${2#v} ;;
		esac
		shift 2
		;;
	*) usage ;;
	esac
done

command -v jq >/dev/null 2>&1 || die "jq is required"
command -v git >/dev/null 2>&1 || die "git is required"
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
sha=$(git rev-parse --verify --quiet "$ref^{commit}") || die "unknown ref: $ref"

version=$(git show "$sha:.claude-plugin/plugin.json" 2>/dev/null | jq -r '.version // empty') ||
	die "no valid .claude-plugin/plugin.json at $ref"
[ -n "$version" ] || die "plugin.json at $ref has no version"
if [ -n "$expect" ] && [ "$expect" != "$version" ]; then
	echo "t4l-package: plugin.json at $ref says $version, expected $expect" >&2
	exit 1
fi

mkdir -p "$out" || die "cannot create $out"
zip="$out/t4l-$version.zip"
git archive --format=zip -o "$zip" "$sha" .claude-plugin rules skills agents hooks scripts README.md ||
	die "git archive failed"
echo "$zip"
