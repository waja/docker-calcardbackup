FROM alpine:3.17.2

ARG BUILD_DATE
ARG BUILD_VERSION
ARG VCS_URL
ARG VCS_REF
ARG VCS_BRANCH

ENV GIT_PROJECT=BernieO/calcardbackup
ENV CALCARDBACKUP_VERSION 5.1.0

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
  apk --no-cache add bash curl findutils mysql-client postgresql-client sqlite gzip && \
  # Create backup dir and make our start script executable
  mkdir /backup

VOLUME ["/backup"]

CMD ["/run.sh"]
