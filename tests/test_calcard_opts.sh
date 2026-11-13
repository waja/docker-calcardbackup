#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"
cat >"$tmp_dir/bin/tail" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
cat >"$tmp_dir/bin/supercronic" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$SUPERCRONIC_ARGS"
STUB
chmod +x "$tmp_dir/bin/"*

export PATH="$tmp_dir/bin:$PATH"
export MARIADB_SSL_SKIP=true
export MARIADB_CLIENT_CNF="$tmp_dir/mariadb-client.cnf"
export BACKUP_LOG="$tmp_dir/backup.log"
export CRONTAB_FILE="$tmp_dir/crontab.conf"
export CAPTURED_CRONTAB="$tmp_dir/captured-crontab"
export CROND_ARGS="$tmp_dir/crond-args"
export INIT_BACKUP=
export CRON_TIME="5 4 * * *"
export CALCARD_OPTS="--custom-flag --keep-existing"

"$repo_root/run.sh"

grep -Fxq '[client]' "$MARIADB_CLIENT_CNF"
grep -Fxq 'skip-ssl = true' "$MARIADB_CLIENT_CNF"
grep -Fq '/opt/calcardbackup/calcardbackup /nextcloud/ --output /backup/ --custom-flag --keep-existing --read-mysql-optionfiles' "$CRONTAB_FILE"
grep -Fxq -- "$CRONTAB_FILE" "$SUPERCRONIC_ARGS"

printf 'run.sh preserves custom CALCARD_OPTS when MARIADB_SSL_SKIP=true\n'
