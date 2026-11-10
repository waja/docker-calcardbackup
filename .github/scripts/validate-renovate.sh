#!/usr/bin/env bash
# Live integration check for the Renovate Codeberg datasource; run with Bash.
set -Eeuo pipefail

# shellcheck source=.github/scripts/classify-renovate-error.sh
source .github/scripts/classify-renovate-error.sh

RENOVATE_IMAGE="${RENOVATE_IMAGE:-renovate/renovate:44.22.0}"
CURRENT_VERSION="$(awk 'tolower($1) == "env" && $2 == "CALCARDBACKUP_VERSION" { print $3; exit }' Dockerfile)"
if [[ -z "$CURRENT_VERSION" ]]; then
	echo "Could not read CALCARDBACKUP_VERSION from Dockerfile." >&2
	exit 1
fi

LOG_FILE="$(mktemp)"
DEPENDENCY_LOG="$(mktemp)"
trap 'rm -f "$LOG_FILE" "$DEPENDENCY_LOG"' EXIT

set +e
docker run --rm \
	--volume "$PWD:/usr/src/app" \
	--workdir /usr/src/app \
	--env LOG_LEVEL=debug \
	"$RENOVATE_IMAGE" \
	--platform=local --dry-run=lookup 2>&1 | tee "$LOG_FILE"
PIPE_STATUS=("${PIPESTATUS[@]}")
set -e
RENOVATE_STATUS="${PIPE_STATUS[0]}"

if [[ "$RENOVATE_STATUS" -ne 0 ]]; then
	if [[ "$(classify_renovate_error "$LOG_FILE")" == "upstream" ]]; then
		echo "::error title=Codeberg datasource unavailable::Renovate could not complete its lookup because the log contains a network, TLS, rate-limit, or upstream HTTP error. This is an infrastructure/datasource outage, not proof of a configuration regression."
	else
		echo "::error title=Renovate lookup failed::Renovate exited with status $RENOVATE_STATUS without a recognized network/upstream error. Inspect the lookup log for a configuration or runtime regression."
	fi
	tail -n 40 "$LOG_FILE" >&2
	exit "$RENOVATE_STATUS"
fi

for expected in \
	'"depNameTemplate": "BernieO/calcardbackup"' \
	'"packageNameTemplate": "BernieO/calcardbackup"' \
	'"datasourceTemplate": "forgejo-tags"' \
	'"registryUrlTemplate": "https://codeberg.org"'; do
	if ! grep -Fq "$expected" "$LOG_FILE"; then
		echo "Renovate did not load the expected custom-manager setting: $expected" >&2
		exit 1
	fi
done

if ! grep -Fq '"depName": "BernieO/calcardbackup"' "$LOG_FILE"; then
	if [[ "$(classify_renovate_error "$LOG_FILE")" == "upstream" ]]; then
		echo "::error title=Codeberg datasource unavailable::Renovate ran but the log indicates a network, TLS, rate-limit, or upstream HTTP problem; the live check is inconclusive."
	else
		echo "::error title=Renovate configuration regression::Renovate completed without a recognizable upstream error but did not discover BernieO/calcardbackup."
	fi
	tail -n 40 "$LOG_FILE" >&2
	exit 1
fi

awk '
	index($0, "\"depName\": \"BernieO/calcardbackup\"") {
		capture = 1
		depth = 1
	}
	capture {
		print
		open_count = gsub(/\{/, "{")
		close_count = gsub(/\}/, "}")
		depth += open_count - close_count
		if (depth == 0) {
			exit
		}
	}
' "$LOG_FILE" >"$DEPENDENCY_LOG"

if ! grep -Fq "\"currentValue\": \"$CURRENT_VERSION\"" "$DEPENDENCY_LOG"; then
	echo "Renovate did not extract CALCARDBACKUP_VERSION=$CURRENT_VERSION." >&2
	exit 1
fi

if ! grep -Fq '"datasource": "forgejo-tags"' "$DEPENDENCY_LOG"; then
	echo "Renovate did not select the forgejo-tags datasource." >&2
	exit 1
fi

if ! grep -Fq '"sourceUrl": "https://codeberg.org/BernieO/calcardbackup"' "$DEPENDENCY_LOG"; then
	echo "Renovate did not return the expected Codeberg source URL." >&2
	exit 1
fi

NEW_VERSION="$(sed -n 's/.*"newVersion": "\([^"]*\)".*/\1/p' "$DEPENDENCY_LOG" | head -n 1)"
NEW_VALUE="$(sed -n 's/.*"newValue": "\([^"]*\)".*/\1/p' "$DEPENDENCY_LOG" | head -n 1)"
MOST_RECENT_TIMESTAMP="$(sed -n 's/.*"mostRecentTimestamp": "\([^"]*\)".*/\1/p' "$DEPENDENCY_LOG" | head -n 1)"
CURRENT_VERSION_TIMESTAMP="$(sed -n 's/.*"currentVersionTimestamp": "\([^"]*\)".*/\1/p' "$DEPENDENCY_LOG" | head -n 1)"

if [[ -n "$NEW_VERSION" ]]; then
	if [[ ! "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ "$NEW_VALUE" != "$NEW_VERSION" ]]; then
		echo "Renovate did not normalize the v-prefixed Codeberg tag to semver (newVersion='$NEW_VERSION', newValue='$NEW_VALUE')." >&2
		exit 1
	fi
	echo "Codeberg returned a normalized calcardbackup update: $CURRENT_VERSION -> $NEW_VERSION."
elif [[ -n "$MOST_RECENT_TIMESTAMP" && -n "$CURRENT_VERSION_TIMESTAMP" ]]; then
	if [[ "$MOST_RECENT_TIMESTAMP" > "$CURRENT_VERSION_TIMESTAMP" ]]; then
		echo "Codeberg has a tag newer than the current version, but Renovate returned no newVersion." >&2
		exit 1
	fi
	echo "Codeberg lookup succeeded; no newer calcardbackup version is available."
else
	echo "Renovate returned no complete Codeberg release metadata; treating this as a failed integration check, not a pass." >&2
	exit 1
fi
