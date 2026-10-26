#!/bin/sh
# Create <repo>/.t4l/config for the current git repository by detecting its stack.
# Usage: t4l-init.sh [--force]
# Supports Go (go.mod) and TypeScript/JavaScript (package.json). Never overwrites
# an existing config without --force.

set -eu

force=0
[ "${1:-}" = "--force" ] && force=1

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
	echo "t4l-init: not inside a git repository" >&2
	exit 1
}
cfg="$root/.t4l/config"

if [ -f "$cfg" ] && [ "$force" -ne 1 ]; then
	echo "t4l-init: $cfg already exists (use --force to overwrite)" >&2
	exit 1
fi

quick=""
quick_ext=""
verify=""

if [ -f "$root/go.mod" ]; then
	quick='go vet ./{dir} && go test ./{dir}'
	quick_ext="go"
	verify='go vet ./... && go test ./...'
	for f in .golangci.yml .golangci.yaml .golangci.toml .golangci.json; do
		if [ -f "$root/$f" ] && command -v golangci-lint >/dev/null 2>&1; then
			verify="$verify && golangci-lint run"
			break
		fi
	done
fi

if [ -f "$root/package.json" ]; then
	if [ -f "$root/pnpm-lock.yaml" ]; then
		pm=pnpm
	elif [ -f "$root/bun.lock" ] || [ -f "$root/bun.lockb" ]; then
		pm=bun
	else
		pm=npm
	fi
	ts_verify=""
	for s in test lint typecheck; do
		if grep -q "\"$s\"[[:space:]]*:" "$root/package.json"; then
			if [ "$s" = test ] && grep -q 'no test specified' "$root/package.json"; then
				continue
			fi
			ts_verify="${ts_verify:+$ts_verify && }$pm run $s"
		fi
	done
	if [ -n "$ts_verify" ]; then
		verify="${verify:+$verify && }$ts_verify"
	fi
	if [ -z "$quick_ext" ]; then
		quick_ext="ts,tsx,js,jsx,mts,cts"
	fi
fi

if [ -z "$verify" ] && [ -z "$quick" ]; then
	echo "t4l-init: no Go or Node project detected; writing an empty config to fill in" >&2
fi

mkdir -p "$root/.t4l"
{
	echo "# t4l verification config. KEY=VALUE, one per line, no quotes."
	echo "# {dir} and {file} are replaced with the edited file's directory and path (relative to the repo root)."
	echo "# Run after every Edit/Write of a file whose extension is in quick_ext:"
	echo "quick=$quick"
	echo "quick_ext=$quick_ext"
	echo "quick_timeout=60"
	echo "# Run before the agent ends a turn, only if the working tree has changes:"
	echo "verify=$verify"
	echo "verify_timeout=300"
	echo "# Set to 1 to turn the hooks off for this repo:"
	echo "disable=0"
} >"$cfg"

gi="$root/.gitignore"
if ! { [ -f "$gi" ] && grep -qx '\.t4l/' "$gi"; }; then
	printf '.t4l/\n' >>"$gi"
	echo "t4l-init: added .t4l/ to .gitignore"
fi

echo "t4l-init: wrote $cfg"
cat "$cfg"
