# Release archive integrity

## Current state

The Dockerfile downloads the generated source archive for the selected
calcardbackup tag from Codeberg and extracts it during the image build.

TLS protects the transport, but it does not independently prove that the
downloaded bytes correspond to the intended release. A checksum downloaded
from the same endpoint as the archive would detect accidental corruption, but
would not provide an independent authenticity guarantee if both files could
be replaced together.

Codeberg documents source archives as snapshots associated with Git tags and
releases. A verified checksum or signature for the current release artifacts has not yet
been established as an available upstream input for this image build.

## Verification design

Before implementing enforcement, establish an upstream trust anchor:

1. Prefer an upstream-published SHA-256 checksum for the exact archive, with a
   detached signature over the checksum file.
2. Verify the signature against a maintainer public key whose fingerprint is
   obtained independently of the archive download.
3. Verify the archive digest before extraction.
4. Fail the build on missing metadata, invalid signatures, or digest mismatch.

A signed Git tag may be an alternative only if the signing key and tag
verification policy are independently established and the downloaded archive
can be tied unambiguously to the verified tag tree.

## Why this is a draft

Do not add a hardcoded digest for only the current release, silently skip
verification when metadata is missing, or fetch an unsigned checksum from the
same origin and describe that as authenticity verification. Those approaches
would create a misleading security guarantee and would break unattended
Renovate updates for future releases.

The next step is to confirm with the calcardbackup maintainer whether signed
checksums, signed tags, or another verifiable release manifest can be
published consistently for every release.
