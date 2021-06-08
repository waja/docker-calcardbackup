FROM alpine:3.13

ARG BUILD_DATE
ARG BUILD_VERSION
ARG VCS_URL
ARG VCS_REF
ARG VCS_BRANCH

ENV GIT_PROJECT=BernieO/calcardbackup

# See http://label-schema.org/rc1/ and https://microbadger.com/labels
LABEL org.label-schema.name="calcardbackup - ownCloud/Nextcloud backup tool" \
    org.label-schema.description="backup calendars and addressbooks from a local ownCloud/Nextcloud installation on Alpine Linux based container" \
    org.label-schema.vendor="Cyconet" \
    org.label-schema.schema-version="1.0" \
    org.label-schema.build-date="${BUILD_DATE:-unknown}" \
    org.label-schema.version="${BUILD_VERSION:-unknown}" \
    org.label-schema.vcs-url="${VCS_URL:-unknown}" \
    org.label-schema.vcs-ref="${VCS_REF:-unknown}" \
    org.label-schema.vcs-branch="${VCS_BRANCH:-unknown}" \
    org.opencontainers.image.source="https://github.com/Cyconet/docker-calcardbackup"

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
RUN curl -L "$(curl -s https://codeberg.org/api/v1/repos/$GIT_PROJECT/releases | jq -r ".[0].tarball_url")" | tar xz --strip=1 && \
  # Remove build deps
  apk del build-dependencies && \
  # Install needed packages
  apk --no-cache add bash curl findutils mysql-client postgresql-client sqlite gzip && \
  # Create backup dir and make our start script executable
  mkdir /backup

VOLUME ["/backup"]

CMD ["/run.sh"]
