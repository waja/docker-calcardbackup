#!/usr/bin/env bash
set -euo pipefail

: "${DOCKER_IMAGE:?DOCKER_IMAGE must be set}"
: "${GITHUB_EVENT_NAME:?GITHUB_EVENT_NAME must be set}"

# Authenticate only against registries for which credentials were supplied.
if [ -n "${GITHUB_TOKEN:-}" ]; then
	printf '%s' "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_ACTOR" --password-stdin
fi
if [ -n "${DOCKERHUB_USERNAME:-}" ] && [ -n "${DOCKERHUB_TOKEN:-}" ]; then
	printf '%s' "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin
fi
if [ -n "${QUAY_USERNAME:-}" ] && [ -n "${QUAY_TOKEN:-}" ]; then
	printf '%s' "$QUAY_TOKEN" | docker login quay.io -u "$QUAY_USERNAME" --password-stdin
fi

if ! release_tags="$(git tag --list)"; then
	echo "::error::Unable to enumerate Git release tags"
	exit 1
fi
releases="$(printf '%s\n' "$release_tags" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$' | sort -V || true)"
if [ -z "$releases" ]; then
	if [ "$GITHUB_EVENT_NAME" = "delete" ] || [ "${EVENT_DELETED:-false}" = "true" ]; then
		echo "::error::No release tags remain. Remove any orphaned release aliases manually; generic manifest deletion could also remove exact version tags."
		exit 1
	fi
	exit 0
fi

registries=()
if [ -n "${DOCKERHUB_USERNAME:-}" ] && [ -n "${DOCKERHUB_TOKEN:-}" ]; then
	registries+=(docker.io)
fi
if [ -n "${GITHUB_TOKEN:-}" ]; then
	registries+=(ghcr.io)
fi
if [ -n "${QUAY_USERNAME:-}" ] && [ -n "${QUAY_TOKEN:-}" ]; then
	registries+=(quay.io)
fi
(("${#registries[@]}")) || exit 0

inspect_image() {
	local image="$1"
	local output
	if output=$(docker buildx imagetools inspect "$image" 2>&1); then
		return 0
	fi
	if printf '%s\n' "$output" | grep -Eiq 'manifest[_ -]unknown|no such manifest' ||
		printf '%s\n' "$output" | grep -Fqx -- "$image: not found" ||
		printf '%s\n' "$output" | grep -Fqx -- "ERROR: $image: not found"; then
		return 1
	fi
	echo "::error::Unable to inspect $image: $output"
	return 2
}

# Determine the highest releases from the union of published images.
# Missing tags are skipped; any other inspection error aborts before aliases
# are changed, avoiding accidental rollback on transient registry failures.
declare -A image_available=()
available_releases=()
inspection_failed=false
for version in $releases; do
	version_available=false
	for registry in "${registries[@]}"; do
		source_image="$registry/$DOCKER_IMAGE:$version"
		if inspect_image "$source_image"; then
			image_available["$registry:$version"]=true
			version_available=true
		else
			inspect_status=$?
			if [ "$inspect_status" -eq 2 ]; then
				inspection_failed=true
			fi
		fi
	done
	[ "$version_available" = true ] && available_releases+=("$version")
done
if [ "$inspection_failed" = true ]; then
	echo "::error::Release image inspection failed; no aliases were changed"
	exit 1
fi
if (("${#available_releases[@]}" == 0)); then
	echo "::error::No published release images are available; refusing to silently skip alias reconciliation"
	deleted_tag="${EVENT_REF:-}"
	deleted_tag="${deleted_tag#refs/tags/}"
	if { [ "$GITHUB_EVENT_NAME" = "delete" ] || [ "${EVENT_DELETED:-false}" = "true" ]; } &&
		[[ "$deleted_tag" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)-[0-9]+$ ]]; then
		echo "::warning::No replacement release image could be identified for deleted release $deleted_tag; manually inspect and remove any orphaned aliases for ${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}, ${BASH_REMATCH[1]}.${BASH_REMATCH[2]}, and ${BASH_REMATCH[1]} in configured registries"
	fi
	exit 1
fi

# Warn about aliases that no remaining release can replace. Deletion is
# deliberately manual: generic manifest deletion could remove exact tags too.
deleted_tag="${EVENT_REF:-}"
deleted_tag="${deleted_tag#refs/tags/}"
if { [ "$GITHUB_EVENT_NAME" = "delete" ] || [ "${EVENT_DELETED:-false}" = "true" ]; } &&
	[[ "$deleted_tag" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)-[0-9]+$ ]]; then
	deleted_major="${BASH_REMATCH[1]}"
	deleted_minor="${BASH_REMATCH[2]}"
	deleted_patch="${BASH_REMATCH[3]}"
	if ! printf '%s\n' "${available_releases[@]}" | grep -Eq "^$deleted_major\.$deleted_minor\.$deleted_patch-"; then
		echo "::warning::Orphaned release alias $deleted_major.$deleted_minor.$deleted_patch has no remaining release; remove it manually from configured registries"
	fi
	if ! printf '%s\n' "${available_releases[@]}" | grep -Eq "^$deleted_major\.$deleted_minor\."; then
		echo "::warning::Orphaned release alias $deleted_major.$deleted_minor has no remaining release; remove it manually from configured registries"
	fi
	if ! printf '%s\n' "${available_releases[@]}" | grep -Eq "^$deleted_major\."; then
		echo "::warning::Orphaned release alias $deleted_major has no remaining release; remove it manually from configured registries"
	fi
fi

registry_releases="$(printf '%s\n' "${available_releases[@]}")"
highest() {
	printf '%s\n' "$registry_releases" | grep -E "$1" | tail -n 1 || true
}
last_index=$(("${#available_releases[@]}" - 1))
latest_version="${available_releases[$last_index]}"

# Build a complete alias plan before changing any registry. A configured
# registry missing a selected source image is inconsistent; fail visibly.
declare -a alias_plan=()
preflight_failed=false
for version in "${available_releases[@]}"; do
	[[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)-[0-9]+$ ]] || continue
	major="${BASH_REMATCH[1]}"
	minor="${BASH_REMATCH[2]}"
	patch="${BASH_REMATCH[3]}"
	aliases=()

	[ "$version" = "$(highest "^$major\.$minor\.$patch-")" ] && aliases+=("$major.$minor.$patch")
	[ "$version" = "$(highest "^$major\.$minor\.")" ] && aliases+=("$major.$minor")
	[ "$version" = "$(highest "^$major\.")" ] && aliases+=("$major")
	[ "$version" = "$latest_version" ] && aliases+=(latest)
	(("${#aliases[@]}")) || continue

	for alias in "${aliases[@]}"; do
		for registry in "${registries[@]}"; do
			if [ "${image_available["$registry:$version"]:-false}" != true ]; then
				echo "::error::Cannot reconcile $alias: selected source $registry/$DOCKER_IMAGE:$version is missing"
				preflight_failed=true
			else
				alias_plan+=("$registry|$alias|$version")
			fi
		done
	done
done
if [ "$preflight_failed" = true ]; then
	echo "::error::At least one configured registry is missing a selected release image; no aliases were changed. Restore the exact release tags and rerun."
	exit 1
fi

publication_failed=false
for entry in "${alias_plan[@]}"; do
	IFS='|' read -r registry alias version <<<"$entry"
	source_image="$registry/$DOCKER_IMAGE:$version"
	target_image="$registry/$DOCKER_IMAGE:$alias"
	published=false
	for attempt in 1 2 3; do
		if docker buildx imagetools create --tag "$target_image" "$source_image"; then
			published=true
			break
		fi
		echo "::warning::Attempt $attempt/3 failed to publish $target_image from $source_image"
		if [ "$attempt" -lt 3 ]; then
			sleep $((attempt * 2))
		fi
	done
	if [ "$published" != true ]; then
		echo "::error::Failed to publish $target_image from $source_image after 3 attempts"
		publication_failed=true
	fi
done

if [ "$publication_failed" = true ]; then
	echo "::error::One or more release aliases could not be published after retries; rerun this job to reconcile all aliases"
	exit 1
fi
