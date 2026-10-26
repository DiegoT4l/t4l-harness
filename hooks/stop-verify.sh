#!/bin/sh
# Stop: run the repo's full verification before the agent ends its turn.
# Only runs when the working tree has changes. If verification fails it exits 2
# once, so the agent keeps working; stop_hook_active prevents a loop.

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

[ "${T4L_HOOKS:-}" = off ] && exit 0

t4l_read_input
t4l_stop_hook_active && exit 0

cwd=$(t4l_json '.cwd' cwd)
[ -n "$cwd" ] || cwd=$PWD
root=$(t4l_repo_root "$cwd") || exit 0
t4l_load_config "$root" || exit 0
[ -n "$CFG_VERIFY" ] || exit 0

# Changes under .t4l/ (the config itself, reports) do not count as work to verify.
[ -n "$(git -C "$root" status --porcelain -- . ':!.t4l' 2>/dev/null)" ] || exit 0

out=$(t4l_run "$root" "$CFG_VERIFY_TIMEOUT" "$CFG_VERIFY")
rc=$?
[ "$rc" -eq 0 ] && exit 0

{
	printf 't4l verify failed (exit %s)\n$ %s\n' "$rc" "$CFG_VERIFY"
	printf '%s\n' "$out" | tail -n 60
	printf 'Fix the failures. If you cannot, tell the user exactly which checks fail and why.\n'
} >&2
exit 2
