#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/reconcile-release-aliases.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin"

cat >"$tmp_dir/bin/git" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = tag ] && [ "$2" = --list ]; then
  if [ "${MOCK_GIT_TAG_LIST_FAIL:-false}" = true ]; then
    echo "simulated git tag failure" >&2
    exit 1
  fi
  printf '%s\n' "${MOCK_RELEASE_TAGS:-}"
  exit 0
fi
echo "unexpected git invocation: $*" >&2
exit 99
STUB

cat >"$tmp_dir/bin/docker" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = login ]; then
  cat >/dev/null
  exit 0
fi
if [ "$1" = buildx ] && [ "$2" = imagetools ] && [ "$3" = inspect ]; then
  image="$4"
  case " ${MOCK_TRANSIENT_IMAGES:-} " in
    *" $image "*) echo "temporary registry failure" >&2; exit 1 ;;
  esac
  case " ${MOCK_MISSING_IMAGES:-} " in
    *" $image "*) echo "manifest unknown" >&2; exit 1 ;;
  esac
  exit 0
fi
if [ "$1" = buildx ] && [ "$2" = imagetools ] && [ "$3" = create ]; then
  target="$5"
  printf '%s\n' "$*" >>"$MOCK_CREATE_LOG"
  if [ "$target" = "${MOCK_CREATE_FAIL_TARGET:-}" ]; then
    attempts="$(cat "$MOCK_CREATE_ATTEMPTS_FILE" 2>/dev/null || printf '0')"
    attempts=$((attempts + 1))
    printf '%s\n' "$attempts" >"$MOCK_CREATE_ATTEMPTS_FILE"
    if [ "$attempts" -le "${MOCK_CREATE_FAIL_COUNT:-0}" ]; then
      echo "temporary publication failure" >&2
      exit 1
    fi
  fi
  printf '%s\n' "$*" >>"$MOCK_PUBLISH_LOG"
  exit 0
fi
echo "unexpected docker invocation: $*" >&2
exit 99
STUB

cat >"$tmp_dir/bin/sleep" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$tmp_dir/bin/"*

# Keep the test registry selection independent of the caller's environment.
unset DOCKERHUB_USERNAME DOCKERHUB_TOKEN QUAY_USERNAME QUAY_TOKEN
export PATH="$tmp_dir/bin:$PATH"
export DOCKER_IMAGE=waja/calcardbackup
export GITHUB_EVENT_NAME=push
export GITHUB_ACTOR=test
export GITHUB_TOKEN=token
export MOCK_PUBLISH_LOG="$tmp_dir/publish.log"
export MOCK_CREATE_LOG="$tmp_dir/create.log"
export MOCK_CREATE_ATTEMPTS_FILE="$tmp_dir/create-attempts"
: >"$MOCK_PUBLISH_LOG"
: >"$MOCK_CREATE_LOG"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}
assert_contains() {
	grep -Fq -- "$2" "$1" || fail "expected '$2' in $1"
}
assert_count() {
	local actual
	actual="$(grep -Fc -- "$2" "$1" || true)"
	[ "$actual" -eq "$3" ] || fail "expected $3 occurrences of '$2' in $1, got $actual"
}

# Highest patch/minor/major and latest aliases are selected independently.
export MOCK_RELEASE_TAGS=$'1.2.0-1\n1.2.0-2\n1.3.0-1\n2.0.0-1'
"$script"
[ "$(wc -l <"$MOCK_PUBLISH_LOG")" -eq 9 ] || fail "expected nine alias publications"
assert_contains "$MOCK_PUBLISH_LOG" '--tag ghcr.io/waja/calcardbackup:1.2.0 ghcr.io/waja/calcardbackup:1.2.0-2'
assert_contains "$MOCK_PUBLISH_LOG" '--tag ghcr.io/waja/calcardbackup:1.2 ghcr.io/waja/calcardbackup:1.2.0-2'
assert_contains "$MOCK_PUBLISH_LOG" '--tag ghcr.io/waja/calcardbackup:1 ghcr.io/waja/calcardbackup:1.3.0-1'
assert_contains "$MOCK_PUBLISH_LOG" '--tag ghcr.io/waja/calcardbackup:latest ghcr.io/waja/calcardbackup:2.0.0-1'

# A failed tag enumeration must abort rather than masquerade as no releases.
: >"$MOCK_PUBLISH_LOG"
export MOCK_GIT_TAG_LIST_FAIL=true
if "$script" >"$tmp_dir/git-failure.log" 2>&1; then
	fail "git tag enumeration failure unexpectedly succeeded"
fi
assert_contains "$tmp_dir/git-failure.log" 'Unable to enumerate Git release tags'
[ ! -s "$MOCK_PUBLISH_LOG" ] || fail "published aliases after git tag enumeration failed"
unset MOCK_GIT_TAG_LIST_FAIL

# A genuinely missing image is skipped; a transient inspection error aborts.
: >"$MOCK_PUBLISH_LOG"
: >"$MOCK_CREATE_LOG"
export MOCK_MISSING_IMAGES='ghcr.io/waja/calcardbackup:2.0.0-1'
"$script"
assert_contains "$MOCK_PUBLISH_LOG" '--tag ghcr.io/waja/calcardbackup:latest ghcr.io/waja/calcardbackup:1.3.0-1'
if grep -Fq -- 'ghcr.io/waja/calcardbackup:2.0.0-1' "$MOCK_CREATE_LOG"; then
	fail "published an alias from the missing release image"
fi
export MOCK_MISSING_IMAGES=
export MOCK_TRANSIENT_IMAGES='ghcr.io/waja/calcardbackup:2.0.0-1'
: >"$MOCK_PUBLISH_LOG"
if "$script" >"$tmp_dir/transient.log" 2>&1; then fail "transient inspect failure unexpectedly succeeded"; fi
[ ! -s "$MOCK_PUBLISH_LOG" ] || fail "published aliases after transient inspection failure"
assert_contains "$tmp_dir/transient.log" 'no aliases were changed'
export MOCK_TRANSIENT_IMAGES=

# All-registry preflight must finish before publishing anything.
export DOCKERHUB_USERNAME=user
export DOCKERHUB_TOKEN=token
export MOCK_MISSING_IMAGES='docker.io/waja/calcardbackup:2.0.0-1'
: >"$MOCK_PUBLISH_LOG"
if "$script" >"$tmp_dir/preflight.log" 2>&1; then fail "incomplete registry unexpectedly passed preflight"; fi
[ ! -s "$MOCK_PUBLISH_LOG" ] || fail "published aliases before all-registry preflight completed"
assert_contains "$tmp_dir/preflight.log" 'no aliases were changed'
unset DOCKERHUB_USERNAME DOCKERHUB_TOKEN
export MOCK_MISSING_IMAGES=

# Deleted release scopes without replacements are reported, never deleted.
export GITHUB_EVENT_NAME=delete
export EVENT_REF=refs/tags/1.2.0-2
export MOCK_RELEASE_TAGS=$'1.3.0-1\n2.0.0-1'
: >"$MOCK_PUBLISH_LOG"
"$script" >"$tmp_dir/deletion.log" 2>&1
assert_contains "$tmp_dir/deletion.log" 'Orphaned release alias 1.2.0'
assert_contains "$tmp_dir/deletion.log" 'Orphaned release alias 1.2'

# A publication that fails twice must succeed on the third attempt.
export GITHUB_EVENT_NAME=push
export MOCK_RELEASE_TAGS=$'1.2.0-1\n1.2.0-2\n1.3.0-1\n2.0.0-1'
unset EVENT_REF
export MOCK_CREATE_FAIL_TARGET='ghcr.io/waja/calcardbackup:1.2.0'
export MOCK_CREATE_FAIL_COUNT=2
: >"$MOCK_CREATE_LOG"
: >"$MOCK_PUBLISH_LOG"
rm -f "$MOCK_CREATE_ATTEMPTS_FILE"
"$script" >"$tmp_dir/retry.log" 2>&1
assert_count "$MOCK_CREATE_LOG" '--tag ghcr.io/waja/calcardbackup:1.2.0 ' 3
assert_contains "$MOCK_PUBLISH_LOG" '--tag ghcr.io/waja/calcardbackup:1.2.0 ghcr.io/waja/calcardbackup:1.2.0-2'
assert_contains "$tmp_dir/retry.log" 'Attempt 1/3 failed'
assert_contains "$tmp_dir/retry.log" 'Attempt 2/3 failed'

# A permanently failing alias is attempted three times, reported as failure,
# and does not prevent later aliases in the precomputed plan from being tried.
export MOCK_CREATE_FAIL_COUNT=3
: >"$MOCK_CREATE_LOG"
: >"$MOCK_PUBLISH_LOG"
rm -f "$MOCK_CREATE_ATTEMPTS_FILE"
if "$script" >"$tmp_dir/permanent-failure.log" 2>&1; then
	fail "permanent publication failure unexpectedly succeeded"
fi
assert_count "$MOCK_CREATE_LOG" '--tag ghcr.io/waja/calcardbackup:1.2.0 ' 3
assert_contains "$tmp_dir/permanent-failure.log" 'Failed to publish ghcr.io/waja/calcardbackup:1.2.0'
assert_contains "$MOCK_CREATE_LOG" '--tag ghcr.io/waja/calcardbackup:1.2 '
assert_contains "$MOCK_PUBLISH_LOG" '--tag ghcr.io/waja/calcardbackup:latest ghcr.io/waja/calcardbackup:2.0.0-1'

printf 'release alias reconciliation tests passed\n'
