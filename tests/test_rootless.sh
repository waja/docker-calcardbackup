#!/usr/bin/env bash
set -euo pipefail

image_ref="${1:?Usage: $0 IMAGE}"
container_name="calcardbackup-rootless-test-$$"
tmp_dir="$(mktemp -d)"
backup_dir="$tmp_dir/backup"

mkdir -p "$backup_dir"
chmod 0777 "$backup_dir"

cleanup() {
  docker rm --force "$container_name" >/dev/null 2>&1 || true
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  docker logs "$container_name" >&2 2>/dev/null || true
  exit 1
}

docker run --detach \
  --name "$container_name" \
  --user 1000:1000 \
  --read-only \
  --env MARIADB_SSL_SKIP=true \
  --env MARIADB_CLIENT_CNF=/backup/mariadb-client.cnf \
  --env BACKUP_LOG=/backup/backup.log \
  --env CRONTAB_FILE=/backup/crontab.conf \
  --env 'CRON_TIME=0 0 1 1 *' \
  --mount "type=bind,source=$backup_dir,target=/backup" \
  "$image_ref" >/dev/null

# Wait for startup to create all runtime files. The yearly schedule prevents
# the integration test from launching a real backup during this short run.
for ((attempt = 0; attempt < 30; attempt++)); do
  running="$(docker inspect --format '{{.State.Running}}' "$container_name" 2>/dev/null || true)"
  [[ "$running" == "true" ]] || fail "container exited before startup completed"

  if [[ -f "$backup_dir/backup.log" &&
        -f "$backup_dir/crontab.conf" &&
        -f "$backup_dir/mariadb-client.cnf" ]]; then
    break
  fi
  sleep 1
done

[[ -f "$backup_dir/backup.log" ]] || fail "BACKUP_LOG was not created on /backup"
[[ -f "$backup_dir/crontab.conf" ]] || fail "CRONTAB_FILE was not created on /backup"
[[ -f "$backup_dir/mariadb-client.cnf" ]] || fail "MariaDB client configuration was not written to /backup"

grep -Fxq '[client]' "$backup_dir/mariadb-client.cnf" ||
  fail "MariaDB client configuration is missing the [client] group"
grep -Fxq 'skip-ssl = true' "$backup_dir/mariadb-client.cnf" ||
  fail "MariaDB client configuration is missing skip-ssl"

grep -Fq '/opt/calcardbackup/calcardbackup /nextcloud/ --output /backup/ -i --read-mysql-optionfiles >> /backup/backup.log 2>&1' "$backup_dir/crontab.conf" ||
  fail "generated crontab does not use the configured backup and log paths"

# The process runs with the requested UID/GID and can write to its sole
# writable mount.
identity="$(docker exec "$container_name" sh -c 'printf "%s:%s" "$(id -u)" "$(id -g)"')"
[[ "$identity" == "1000:1000" ]] || fail "container is running as $identity instead of 1000:1000"
docker exec "$container_name" sh -c 'test -w /backup/backup.log' ||
  fail "the unprivileged container user cannot write to /backup"

# Verify that the standard MariaDB option-file location resolves into the
# writable backup mount, then exercise the same --defaults-extra-file
# mechanism used by calcardbackup 11.2.0.
link_target="$(docker exec "$container_name" readlink /etc/my.cnf.d/my.cnf)"
[[ "$link_target" == "/backup/mariadb-client.cnf" ]] ||
  fail "MariaDB client configuration symlink points to $link_target"

db_client="$(
  docker exec "$container_name" sh -c '
    if command -v mariadb >/dev/null 2>&1; then
      printf mariadb
    elif command -v mysql >/dev/null 2>&1; then
      printf mysql
    else
      exit 1
    fi
  '
)" || fail "no MariaDB/MySQL client executable found"

defaults_output="$(
  docker exec "$container_name" bash -c '
    client="$1"
    "$client" --defaults-extra-file=<(printf "%s\n" \
      "[client]" \
      "user = rootless-test" \
      "password = placeholder" \
      "default_character_set = utf8mb4") --print-defaults
  ' _ "$db_client"
)"
printf '%s\n' "$defaults_output"
grep -Fq -- '--skip-ssl' <<<"$defaults_output" ||
  fail "MariaDB client did not load skip-ssl from the global option-file chain"

# PID 1 must be Supercronic, and the image root filesystem must remain
# read-only even when the check is executed as container root.
pid1_comm="$(docker exec "$container_name" cat /proc/1/comm)"
[[ "$pid1_comm" == "supercronic" ]] || fail "PID 1 is '$pid1_comm', not supercronic"

if docker exec --user 0 "$container_name" sh -c 'touch /etc/rootless-test-write' >/dev/null 2>&1; then
  fail "the container root filesystem is writable despite --read-only"
fi

printf 'Rootless container integration test passed for %s\n' "$image_ref"
