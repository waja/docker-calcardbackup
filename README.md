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
```cmd
docker container run -d \
    --link mysql \
    --volume /path/to/my/backup/folder:/backup \
    --volume /path/to/my/nextcloud/config:/nextcloud/config \
    waja/calcardbackup
```
<!-- textlint-enable -->

## Running rootlessly as a dedicated user

As cron jobs are scheduled by [supercronic](https://github.com/aptible/supercronic), it is possible to deploy this image in rootless mode with a dedicated user.

The user running the container must have following permissions:

- read access to the nexcloud config path (`/path/to/my/nextcloud/config`)
- write access to further mounted host paths (`/path/to/my/backup/folder` etc.)
- access to nextcloud's database (`SELECT` priviledge at a minimum)

Additionally, all files changing at runtime such as `BACKUP_LOG`, `CRONTAB_FILE` and `MARIADB_CLIENT_CNF` must point to writable mounts or volumes inside the container, for instance `/backup`:

```env
BACKUP_LOG=/backup/backup.log
CRONTAB_FILE=/backup/crontab.conf
MARIADB_CLIENT_CNF=/backup/mariadb-client.cnf
```

Start the rootless container with `--user` and `--read-only` flags. `--user` designates the user with limited priviledges while `--read-only` prevents changes to the core image.
Assuming user with `uid=1000` and `gid=1000` meets above requirements:

```cmd
docker container run -d \
    --user 1000:1000 \
    --read-only \
    --link mysql \
    --volume /path/to/my/backup/folder:/backup \
    --volume /path/to/my/nextcloud/config:/nextcloud/config:ro \
    waja/calcardbackup
```


## Docker compose

There is a [`docker-compose-example.yml`](https://raw.githubusercontent.com/waja/docker-calcardbackup/development/docker-compose-example.yml) and a [`docker-compose-complex-example.yml`](https://raw.githubusercontent.com/waja/docker-calcardbackup/development/docker-compose-complex-example.yml) available. Feel free to have a look if there is something you can use.

## Variables

    CRON_TIME         the interval of cron job to run mysqldump. `5 4 * * *` by default, which is every day at 04:05 (optional)
    INIT_BACKUP       if set, create a backup when the container starts (optional)
    BACKUP_DIR        location where the backup should be stored; defaults to `/backup/` (optional)
    NC_DIR            location where Nextcloud config/config.php is searched for, defaults to `/nextcloud/` (optional)
    NC_HOST           hostname Nextcloud webinterface running on (optional)
    NC_PORT           port Nextcloud webinterface running on; defaults to `443` (optional)
    DB_HOST           hostname database running on (optional)
    DB_PORT           port database running on; defaults to `3306` (optional)
    CALCARD_OPTS      options passed to calcardbackup (optional)
    BACKUP_LOG        log file for startup and scheduled backups; defaults to `/backup.log` (optional)
    CRONTAB_FILE      generated crontab file; defaults to `/crontab.conf` (optional)
    MARIADB_SSL_SKIP  set to 'true' to prevent mariadb client force to use SSL

Both paths may be absolute or relative. Relative paths are resolved against the container's working directory. Parent directories are created during startup; the paths must still be writable. `BACKUP_LOG` must not contain `#`, because it is embedded in the generated cron command.
