#!/usr/bin/env bash
set -Eeuo pipefail

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/bin"

cat >"$tmpdir/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
set -Eeuo pipefail
cat "$FAKE_RENOVATE_LOG"
exit "${FAKE_RENOVATE_STATUS:-0}"
DOCKER
chmod +x "$tmpdir/bin/docker"

current_version="$(awk 'tolower($1) == "env" && $2 == "CALCARDBACKUP_VERSION" { print $3; exit }' Dockerfile)"
cat >"$tmpdir/success.log" <<EOF
{"depNameTemplate": "BernieO/calcardbackup"}
{"packageNameTemplate": "BernieO/calcardbackup"}
{"datasourceTemplate": "forgejo-tags"}
{"registryUrlTemplate": "https://codeberg.org"}
{
  "depName": "BernieO/calcardbackup",
  "currentValue": "$current_version",
  "datasource": "forgejo-tags",
  "sourceUrl": "https://codeberg.org/BernieO/calcardbackup",
  "newVersion": "11.2.0",
  "newValue": "11.2.0"
}
EOF

PATH="$tmpdir/bin:$PATH" FAKE_RENOVATE_LOG="$tmpdir/success.log" \
	FAKE_RENOVATE_STATUS=0 bash .github/scripts/validate-renovate.sh >"$tmpdir/success.out" 2>&1
grep -Fq "normalized calcardbackup update" "$tmpdir/success.out"

cat >"$tmpdir/config.log" <<'EOF'
{"depNameTemplate": "BernieO/calcardbackup"}
{"packageNameTemplate": "BernieO/calcardbackup"}
{"datasourceTemplate": "forgejo-tags"}
{"registryUrlTemplate": "https://codeberg.org"}
custom manager did not discover the dependency
EOF
if PATH="$tmpdir/bin:$PATH" FAKE_RENOVATE_LOG="$tmpdir/config.log" \
	FAKE_RENOVATE_STATUS=0 bash .github/scripts/validate-renovate.sh >"$tmpdir/config.out" 2>&1; then
	echo "Expected configuration-regression scenario to fail." >&2
	exit 1
fi
grep -Fq "::error title=Renovate configuration regression::" "$tmpdir/config.out"

cat >"$tmpdir/network.log" <<'EOF'
ECONNRESET while requesting https://codeberg.org
EOF
if PATH="$tmpdir/bin:$PATH" FAKE_RENOVATE_LOG="$tmpdir/network.log" \
	FAKE_RENOVATE_STATUS=1 bash .github/scripts/validate-renovate.sh >"$tmpdir/network.out" 2>&1; then
	echo "Expected upstream-outage scenario to fail." >&2
	exit 1
fi
grep -Fq "::error title=Codeberg datasource unavailable::" "$tmpdir/network.out"

echo "Renovate live-validation success, regression, and outage tests passed."
