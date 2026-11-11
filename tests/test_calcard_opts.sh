#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
assignment="$(grep -m1 -E '^[[:space:]]*CALCARD_OPTS=.*--read-mysql-optionfiles' "$repo_root/run.sh")"

run_case() {
  local input="$1"
  local expected="$2"
  local actual

  actual="$(CALCARD_OPTS="$input" bash -c "$assignment; printf '%s' \"\$CALCARD_OPTS\"")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'Expected CALCARD_OPTS=%q, got %q\n' "$expected" "$actual" >&2
    exit 1
  fi
}

run_case '--custom-flag --keep-existing' '--custom-flag --keep-existing --read-mysql-optionfiles'
run_case '' '-i --read-mysql-optionfiles'

actual="$(env -u CALCARD_OPTS bash -c "$assignment; printf '%s' \"\$CALCARD_OPTS\"")"
if [[ "$actual" != '-i --read-mysql-optionfiles' ]]; then
  printf 'Expected default CALCARD_OPTS, got %q\n' "$actual" >&2
  exit 1
fi

printf 'CALCARD_OPTS regression checks passed\n'
