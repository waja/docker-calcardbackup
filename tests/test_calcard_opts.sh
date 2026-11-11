#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/calcardbackup-options.bash
source "$repo_root/lib/calcardbackup-options.bash"

run_case() (
	local input="$1"
	local expected="$2"

	if [[ "$input" == "__UNSET__" ]]; then
		unset CALCARD_OPTS
	else
		CALCARD_OPTS="$input"
	fi

	calcardbackup_enable_mysql_optionfiles
	if [[ "$CALCARD_OPTS" != "$expected" ]]; then
		printf 'Expected CALCARD_OPTS=%q, got %q\n' "$expected" "$CALCARD_OPTS" >&2
		exit 1
	fi
)

run_case '--custom-flag --keep-existing' '--custom-flag --keep-existing --read-mysql-optionfiles'
run_case '' '-i --read-mysql-optionfiles'
run_case '__UNSET__' '-i --read-mysql-optionfiles'

printf 'CALCARD_OPTS regression checks passed\n'
