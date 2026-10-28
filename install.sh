#!/bin/sh
# Install the t4l plugin for Claude Code from its marketplace on GitHub.
#
#   curl -fsSL https://raw.githubusercontent.com/DiegoT4l/t4l-harness/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/DiegoT4l/t4l-harness/main/install.sh | sh -s -- --scope project
#
# Options:
#   --scope SCOPE        user (default), project or local; also T4L_SCOPE
#   --marketplace SRC    marketplace source (default: DiegoT4l/t4l-harness); also T4L_MARKETPLACE
#   -h, --help           show this help
# Safe to run again: it refreshes the marketplace and updates the plugin.
# Exit status: 0 installed, 1 a step failed, 2 usage error.

set -u

# Everything runs from main, so a download cut short executes nothing.
main() {
	scope=${T4L_SCOPE:-user}
	source=${T4L_MARKETPLACE:-DiegoT4l/t4l-harness}

	while [ $# -gt 0 ]; do
		case $1 in
		--scope | --marketplace)
			[ $# -ge 2 ] || usage
			case $1 in
			--scope) scope=$2 ;;
			--marketplace) source=$2 ;;
			esac
			shift 2
			;;
		-h | --help)
			show_help
			exit 0
			;;
		*) usage ;;
		esac
	done
	case $scope in
	user | project | local) ;;
	*)
		echo "t4l install: --scope must be user, project or local" >&2
		exit 2
		;;
	esac

	command -v claude >/dev/null 2>&1 || {
		echo "t4l install: the claude command was not found. Install Claude Code first: https://code.claude.com/docs/en/setup" >&2
		exit 1
	}

	step claude plugin marketplace add "$source" --scope "$scope"
	step claude plugin marketplace update t4l-harness
	step claude plugin install t4l@t4l-harness --scope "$scope"
	step claude plugin update t4l@t4l-harness --scope "$scope"

	cat <<EOF

t4l install: installed t4l (scope: $scope).
Restart Claude Code, then run /t4l:setup to check the tools t4l uses
and /t4l:init in a repository to turn on its verification hooks.
EOF
}

# a heredoc, not the comment above: piped into sh, there is no file to read
show_help() {
	cat <<'EOF'
Install the t4l plugin for Claude Code from its marketplace on GitHub.

  curl -fsSL https://raw.githubusercontent.com/DiegoT4l/t4l-harness/main/install.sh | sh
  curl -fsSL https://raw.githubusercontent.com/DiegoT4l/t4l-harness/main/install.sh | sh -s -- --scope project

Options:
  --scope SCOPE        user (default), project or local; also T4L_SCOPE
  --marketplace SRC    marketplace source (default: DiegoT4l/t4l-harness); also T4L_MARKETPLACE
  -h, --help           show this help
Safe to run again: it refreshes the marketplace and updates the plugin.
EOF
}

usage() {
	echo "Usage: install.sh [--scope user|project|local] [--marketplace SOURCE]" >&2
	exit 2
}

step() {
	echo "> $*"
	"$@" || {
		echo "t4l install: failed: $*" >&2
		exit 1
	}
}

main "$@"
