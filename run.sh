#!/bin/bash
if [ "${MARIADB_SSL_SKIP:=false}" == "true" ]; then
	cat >/etc/my.cnf.d/mariadb-client.cnf <<EOF
[client]
skip-ssl = true
EOF
	CALCARD_OPTS="${CALCARD_OPT:=-i} --read-mysql-optionfiles"
fi
BACKUP_CMD="/opt/calcardbackup/calcardbackup ${NC_DIR:=/nextcloud/} --output ${BACKUP_DIR:=/backup/} ${CALCARD_OPTS:=-i}"
BACKUP_LOG="/backup.log"
touch ${BACKUP_LOG}
tail -F ${BACKUP_LOG} &

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
	${BACKUP_CMD} >>${BACKUP_LOG} 2>&1
fi

echo "${CRON_TIME:=5 4 * * *} ${BACKUP_CMD} >> ${BACKUP_LOG} 2>&1" >/crontab.conf
crontab /crontab.conf
echo "=> Running cron task manager"
exec crond -f
