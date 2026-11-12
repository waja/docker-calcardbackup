#!/bin/bash
# shellcheck source=lib/calcardbackup-options.bashlib
OPTIONS_LIB="/opt/calcardbackup/lib/calcardbackup-options.bashlib"
if [[ ! -r "$OPTIONS_LIB" ]]; then
	OPTIONS_LIB="$(dirname "${BASH_SOURCE[0]}")/lib/calcardbackup-options.bashlib"
fi
if [[ ! -r "$OPTIONS_LIB" ]]; then
	echo "Cannot read calcardbackup options library: $OPTIONS_LIB" >&2
	exit 1
fi
source "$OPTIONS_LIB"

if [ "${MARIADB_SSL_SKIP:=false}" == "true" ]; then
	MARIADB_CLIENT_CNF="${MARIADB_CLIENT_CNF:-/etc/my.cnf.d/mariadb-client.cnf}"
	mkdir -p "$(dirname "$MARIADB_CLIENT_CNF")"
	cat >"$MARIADB_CLIENT_CNF" <<EOF
[client]
skip-ssl = true
EOF
	calcardbackup_enable_mysql_optionfiles
fi
BACKUP_CMD="/opt/calcardbackup/calcardbackup ${NC_DIR:=/nextcloud/} --output ${BACKUP_DIR:=/backup/} ${CALCARD_OPTS:=-i}"
BACKUP_LOG="${BACKUP_LOG:-/backup.log}"
touch "${BACKUP_LOG}"
tail -F "${BACKUP_LOG}" &

if [ -n "${INIT_BACKUP}" ]; then
	echo "=> Create a backup on the startup"
	if [ -n "${NC_HOST}" ]; then
		until nc -z "${NC_HOST}" "${NC_PORT:=443}"; do
			echo "waiting for Nextcloud webinterface ..."
			sleep 1
		done
	fi
	if [ -n "${DB_HOST}" ]; then
		until nc -z "${DB_HOST}" "${DB_PORT:=3306}"; do
			echo "waiting for database container ..."
			sleep 1
		done
	fi
	${BACKUP_CMD} >>"${BACKUP_LOG}" 2>&1
fi

CRONTAB_FILE="${CRONTAB_FILE:-/crontab.conf}"
echo "${CRON_TIME:=5 4 * * *} ${BACKUP_CMD} >> ${BACKUP_LOG} 2>&1" >"$CRONTAB_FILE"
echo "=> Running cron task manager"
exec supercronic "$CRONTAB_FILE"
