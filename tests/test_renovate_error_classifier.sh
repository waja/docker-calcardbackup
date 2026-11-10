set -Eeuo pipefail

# shellcheck source=.github/scripts/classify-renovate-error.sh
source .github/scripts/classify-renovate-error.sh

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

printf '%s\n' 'ECONNRESET while requesting Codeberg' >"$tmpdir/network.log"
[[ "$(classify_renovate_error "$tmpdir/network.log")" == "upstream" ]]

printf '%s\n' 'HTTP 503 from upstream' >"$tmpdir/http.log"
[[ "$(classify_renovate_error "$tmpdir/http.log")" == "upstream" ]]

printf '%s\n' 'certificate verify failed' >"$tmpdir/tls.log"
[[ "$(classify_renovate_error "$tmpdir/tls.log")" == "upstream" ]]

printf '%s\n' 'custom manager did not extract a dependency' >"$tmpdir/config.log"
[[ "$(classify_renovate_error "$tmpdir/config.log")" == "configuration" ]]

echo "Renovate error-classifier tests passed."
