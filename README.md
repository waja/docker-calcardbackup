<!-- markdownlint-disable MD045 -->

# Docker-Calcardbackup

[![](https://images.microbadger.com/badges/version/waja/calcardbackup.svg)](https://hub.docker.com/r/waja/calcardbackup/)
[![](https://images.microbadger.com/badges/image/waja/calcardbackup.svg)](https://hub.docker.com/r/waja/calcardbackup/)
[![Build Status](https://travis-ci.org/Cyconet/docker-calcardbackup.svg?branch=development)](https://travis-ci.org/Cyconet/docker-calcardbackup)
[![Docker Build Status](https://img.shields.io/docker/build/waja/calcardbackup.svg)](https://hub.docker.com/r/waja/calcardbackup/)
[![GitHub tag](https://img.shields.io/github/tag/Cyconet/docker-calcardbackup.svg)](https://github.com/Cyconet/docker-calcardbackup/tags)
[![](https://img.shields.io/docker/pulls/waja/calcardbackup.svg)](https://hub.docker.com/r/waja/calcardbackup/)
[![](https://img.shields.io/docker/stars/waja/calcardbackup.svg)](https://hub.docker.com/r/waja/calcardbackup/)
[![](https://img.shields.io/docker/automated/waja/calcardbackup.svg)](https://hub.docker.com/r/waja/calcardbackup/)

## Usage

<!-- textlint-disable -->

docker container run -d \
--link mysql
--volume /path/to/my/backup/folder:/backup
--volume /path/to/my/nextcloud/config:/nextcloud/config
waja/calcardbackup

<!-- textlint-enable -->

## docker compose

There is a [`docker-compose-example.yml`](https://raw.githubusercontent.com/waja/docker-calcardbackup/development/docker-compose-example.yml) and a [`docker-compose-complex-example.yml`](https://raw.githubusercontent.com/waja/docker-calcardbackup/development/docker-compose-complex-example.yml) available. Feel free to have a look if there is something you can use.

## Variables

    CRON_TIME         the interval of cron job to run mysqldump. `5 4 * * *` by default, which is every day at 04:05 (optional)
    INIT_BACKUP       if set, create a backup when the container starts (optional)
    BACKUP_DIR        location where the backup should be stored (optional)
    NC_DIR            location where Nextcloud config/config.php is searched for (optional)
    NC_HOST           hostname Nextcloud webinterface running on (optional)
    NC_PORT           port Nextcloud webinterface running on (optional)
    DB_HOST           hostname database running on (optional)
    DB_PORT           port database running on (optional)
    CALCARD_OPTS      options passed to calcardbackup (optional)
    MARIADB_SSL_SKIP  set to 'true' to prevent mariadb client force to use SSL
