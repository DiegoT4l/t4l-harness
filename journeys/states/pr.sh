#!/bin/sh
# Shared state for journeys: pull request #12 of the slug fixture, not ready to
# merge. Sourced by journey files; runs in the work copy with $BIN set.
# shellcheck disable=SC2154  # BIN is set by t4l-journey.sh
#
# Branch feat/max-len adds Truncate and a --max-len flag. Three things block it:
#   - main moved: both sides appended a line to README.md (merge conflict);
#   - CI fails: go vet rejects a format verb in cmd/slug/main.go;
#   - a review asks for a fix: Truncate keeps a trailing hyphen when len(s) == n.
# A fake gh in $BIN answers for the PR and logs every call to $BIN/../gh.log.

pr_state() {
	git config user.email t4l@example.com
	git config user.name t4l

	git switch -qc feat/max-len
	cat >>internal/slug/slug.go <<'EOF'

// Truncate cuts a slug to at most n characters and drops the hyphen
// the cut may leave at the end.
func Truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return strings.TrimRight(s[:n], "-")
}
EOF
	cat >internal/slug/slug_test.go <<'EOF'
package slug

import "testing"

func TestTruncate(t *testing.T) {
	if got := Truncate("hello-world", 6); got != "hello" {
		t.Fatalf("Truncate = %q, want %q", got, "hello")
	}
}
EOF
	git add -A && git commit -qm "feat(slug): add Truncate"

	cat >cmd/slug/main.go <<'EOF'
package main

import (
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"

	"t4lsandbox/internal/slug"
)

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

func run(args []string, stdout, stderr io.Writer) int {
	limit := 0
	if len(args) >= 2 && args[0] == "--max-len" {
		n, err := strconv.Atoi(args[1])
		if err != nil || n < 1 {
			fmt.Fprintf(stderr, "invalid --max-len %d\n", args[1])
			return 2
		}
		limit, args = n, args[2:]
	}
	if len(args) == 0 {
		fmt.Fprintln(stderr, "usage: slug <text>")
		return 2
	}
	out := slug.Make(strings.Join(args, " "))
	if limit > 0 {
		out = slug.Truncate(out, limit)
	}
	fmt.Fprintln(stdout, out)
	return 0
}
EOF
	cat >cmd/slug/main_test.go <<'EOF'
package main

import (
	"bytes"
	"testing"
)

func TestRunMaxLen(t *testing.T) {
	var out, errb bytes.Buffer
	if code := run([]string{"--max-len", "6", "Hello", "World"}, &out, &errb); code != 0 {
		t.Fatalf("exit %d, stderr %q", code, errb.String())
	}
	if out.String() != "hello\n" {
		t.Fatalf("got %q, want %q", out.String(), "hello\n")
	}
}
EOF
	echo '    go run ./cmd/slug --max-len 6 "Hello, World!"   # expected: hello' >>README.md
	git add -A && git commit -qm "feat(cmd): add the --max-len flag"

	git switch -q main
	echo '    go run ./cmd/slug "Café"   # expected: caf-' >>README.md
	git commit -qam "docs: show what happens to accents"
	git switch -q feat/max-len

	pr_fake_gh
}

pr_fake_gh() {
	_log="$(dirname "$BIN")/gh.log"
	cat >"$BIN/gh" <<EOF
#!/bin/sh
log="$_log"
EOF
	cat >>"$BIN/gh" <<'EOF'
echo "gh $*" >>"$log"

pr_json() {
	cat <<'JSON'
{"number":12,"title":"feat: add --max-len","state":"OPEN","isDraft":false,"url":"https://github.com/acme/slug/pull/12",
 "headRefName":"feat/max-len","baseRefName":"main","mergeable":"CONFLICTING","mergeStateStatus":"DIRTY",
 "reviewDecision":"CHANGES_REQUESTED","body":"Adds slug.Truncate and a --max-len N flag.",
 "author":{"login":"dev"},
 "statusCheckRollup":[{"name":"test","status":"COMPLETED","conclusion":"FAILURE","detailsUrl":"https://github.com/acme/slug/actions/runs/101"}],
 "reviews":[{"author":{"login":"lead-dev"},"state":"CHANGES_REQUESTED","body":"One bug in Truncate, see the inline comment."}],
 "comments":[]}
JSON
}
review_comments() {
	cat <<'JSON'
[{"id":9001,"path":"internal/slug/slug.go","line":23,"user":{"login":"lead-dev"},
  "body":"When len(s) == n and s ends with a hyphen, Truncate keeps it: Truncate(\"hello-\", 6) returns \"hello-\". The flag must never leave a trailing hyphen (slug --max-len 6 \"hello!\" prints hello-). Please fix it and add a test."}]
JSON
}
ci_log() {
	cat <<'LOG'
test	Run go vet ./...	# t4lsandbox/cmd/slug
test	Run go vet ./...	cmd/slug/main.go:22:43: fmt.Fprintf format %d has arg args[1] of wrong type string
test	Run go vet ./...	##[error]Process completed with exit code 1.
LOG
}
jq_flag() { # print the --jq expression, if any
	while [ $# -gt 0 ]; do
		case $1 in --jq | -q) echo "$2"; return ;; --jq=*) echo "${1#--jq=}"; return ;; esac
		shift
	done
}
emit() { # json, filtered by --jq when given
	_q=$(jq_flag "$@")
	if [ -n "$_q" ]; then jq -r "$_q"; else cat; fi
}
has() { # flag
	_f=$1
	shift
	for _a in "$@"; do [ "$_a" = "$_f" ] && return 0; done
	return 1
}

case "$1 $2" in
"pr view")
	if has --json "$@"; then
		pr_json | emit "$@"
	else
		echo "feat: add --max-len #12"
		echo "Open • dev wants to merge 2 commits into main from feat/max-len"
		echo "Reviewers: lead-dev (Changes requested)"
		echo "Checks: 1 failing"
		echo "Merge: conflicts with main"
		has --comments "$@" && review_comments | jq -r '.[] | "\(.user.login) on \(.path):\(.line): \(.body)"'
	fi
	;;
"pr checks")
	printf 'test\tfail\t41s\thttps://github.com/acme/slug/actions/runs/101\n'
	exit 1
	;;
"pr diff") git diff main...feat/max-len ;;
"pr status") echo "Current branch: #12 feat: add --max-len [feat/max-len] - Checks failing - Changes requested - Conflicts" ;;
"run list") printf 'completed\tfailure\tfeat: add --max-len\tCI\tfeat/max-len\tpull_request\t101\t41s\n' ;;
"run view")
	if has --log-failed "$@" || has --log "$@"; then ci_log; else echo "X feat/max-len CI #101 · failed: test (go vet)"; fi
	;;
"api "* | "api")
	case "$*" in
	*-X* | *--method* | *-f\ * | *--field* | *--raw-field* | *-F\ *)
		echo "{}"
		;;
	*graphql*)
		echo "GraphQL: not available in this environment; use gh pr view --json or the REST endpoints" >&2
		exit 1
		;;
	*pulls/12/comments*) review_comments | emit "$@" ;;
	*pulls/12/reviews*) pr_json | jq '.reviews' | emit "$@" ;;
	*issues/12/comments*) echo "[]" | emit "$@" ;;
	*pulls/12*) pr_json | emit "$@" ;;
	*) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
	esac
	;;
"pr comment" | "pr review" | "pr merge" | "pr edit" | "pr ready" | "pr close") echo "done" ;;
"repo view") echo "acme/slug" ;;
"auth status") echo "Logged in to github.com account dev" ;;
*) echo "gh: unsupported command in this environment: $*" >&2; exit 1 ;;
esac
EOF
	chmod +x "$BIN/gh"
}
