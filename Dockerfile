# syntax = docker/dockerfile:1@sha256:b6afd42430b15f2d2a4c5a02b919e98a525b785b1aaff16747d2f623364e39b6
# requires DOCKER_BUILDKIT=1 set when running docker build
# checkov:skip=CKV_DOCKER_2: no healthcheck (yet)
# checkov:skip=CKV_DOCKER_3: no user (yet)
FROM alpine:3.23.0@sha256:51183f2cfa6320055da30872f211093f9ff1d3cf06f39a0bdb212314c5dc7375

ARG BUILD_DATE
ARG BUILD_VERSION
ARG VCS_URL
ARG VCS_REF
ARG VCS_BRANCH

ENV GIT_PROJECT=BernieO/calcardbackup
ENV CALCARDBACKUP_VERSION 9.0.0

# See http://label-schema.org/rc1/ and https://microbadger.com/labels
LABEL maintainer="Jan Wagner <waja@cyconet.org>" \
    org.label-schema.name="calcardbackup - ownCloud/Nextcloud backup tool" \
    org.label-schema.description="backup calendars and addressbooks from a local ownCloud/Nextcloud installation on Alpine Linux based container" \
    org.label-schema.vendor="Cyconet" \
    org.label-schema.schema-version="1.0" \
    org.label-schema.build-date="${BUILD_DATE:-unknown}" \
    org.label-schema.version="${BUILD_VERSION:-unknown}" \
    org.label-schema.vcs-url="${VCS_URL:-unknown}" \
    org.label-schema.vcs-ref="${VCS_REF:-unknown}" \
    org.label-schema.vcs-branch="${VCS_BRANCH:-unknown}" \
    org.opencontainers.image.source="https://github.com/waja/docker-calcardbackup"

COPY ["run.sh", "/"]

# hadolint ignore=DL3017,DL3018
RUN apk --no-cache update && apk --no-cache upgrade && \
  # Install dependencies
  apk --no-cache add --virtual build-dependencies ca-certificates tar curl jq && \
  # Create directory
  mkdir -p /opt/calcardbackup
WORKDIR /opt/calcardbackup
# Download latest release
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
# hadolint ignore=DL3017,DL3018
RUN curl -L "https://codeberg.org/BernieO/calcardbackup/archive/v$CALCARDBACKUP_VERSION.tar.gz" | tar xz --strip=1 && \
  # Remove build deps
  apk del build-dependencies && \
  # Install needed packages
  apk --no-cache add bash curl findutils mysql-client postgresql-client sqlite gzip zip gnupg && \
  # Create backup dir and make our start script executable
  mkdir /backup

VOLUME ["/backup"]

CMD ["/run.sh"]
