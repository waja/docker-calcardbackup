FROM alpine:3.7

# Dockerfile Maintainer
MAINTAINER Jan Wagner "waja@cyconet.org"

COPY ["run.sh", "/"]

# Install dependencies
RUN apk --no-cache add --virtual build-dependencies git ca-certificates && \
  # Pull calcardbackup source
  git clone https://github.com/BernieO/calcardbackup.git /opt/calcardbackup && cd /opt/calcardbackup && \
  # Checkout latest tag
  LATEST_TAG=$(git tag -l 'v*.[0-9]' --sort='v:refname'| tail -1); git checkout $LATEST_TAG -b $LATEST_TAG && \
  # Set global git config
  #git config --global user.name "Jingo Wiki" && git config --global user.email "everyone@jingo" && \
  # Remove build deps
  apk del build-dependencies && \
  # Install needed packages
  apk add --update bash coreutils curl findutils mysql-client postgresql-client sqlite gzip && rm -rf /var/cache/apk/* && \
  # Create backup dir and make our start script executable
  mkdir /backup

VOLUME ["/backup"]

CMD ["/run.sh"]
