#!/bin/bash
BACKUP_CMD="/opt/calcardbackup/calcardbackup --output /backup/ ${CALCARD_OPTS} ${NC_DIR}"
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
