#!/bin/bash
BACKUP_CMD="/opt/calcardbackup/calcardbackup ${NC_DIR:=/nextcloud/} --output ${BACKUP_DIR:=/backup/} ${CALCARD_OPTS:=-i}"
BACKUP_LOG="/backup.log"
touch ${BACKUP_LOG}
tail -F ${BACKUP_LOG} &

if [ -n "${INIT_BACKUP}" ]; then
  echo "=> Create a backup on the startup"
  ${BACKUP_CMD}
fi

echo "${CRON_TIME:=5 4 * * *} ${BACKUP_CMD} >> ${BACKUP_LOG} 2>&1" > /crontab.conf
crontab /crontab.conf
echo "=> Running cron task manager"
exec crond -f
