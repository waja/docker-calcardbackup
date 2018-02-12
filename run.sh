#!/bin/bash
BACKUP_CMD="/opt/calcardbackup/calcardbackup ${NC_DIR} --output /backup/ ${CALCARD_OPTS}"
BACKUP_LOG="/backup.log"
touch ${BACKUP_LOG}
tail -F ${BACKUP_LOG} &

if [ -n "${INIT_BACKUP}" ]; then
  echo "=> Create a backup on the startup"
  ${BACKUP_CMD}
fi

echo "${CRON_TIME} ${BACKUP_CMD} >> ${BACKUP_LOG} 2>&1" > /crontab.conf
crontab /crontab.conf
echo "=> Running cron task manager"
exec crond -f
