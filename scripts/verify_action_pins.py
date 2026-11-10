"""Verify that workflow action SHA pins match their declared version tags."""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ACTION = re.compile(
    r"^\s*(?:-\s*)?uses:\s*([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)(?:/[^@\s]+)?@"
    r"([0-9a-f]{40})\s+#\s*v?([A-Za-z0-9][A-Za-z0-9._+-]*)\s*$"
)
REPOSITORY = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
VERSION = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+-]*$")
ALLOWED_REPOSITORIES = {
    "actions/cache",
    "actions/checkout",
    "actions/download-artifact",
    "actions/setup-node",
    "anchore/scan-action",
    "aquasecurity/trivy-action",
    "docker/build-push-action",
    "docker/login-action",
    "docker/setup-buildx-action",
    "docker/setup-qemu-action",
    "goodwithtech/dockle-action",
    "github/codeql-action",
    "ShiftLeftSecurity/scan-action",
    "super-linter/super-linter",
    "actions/upload-artifact",
}


def api_json(path: str) -> dict:
    """Fetch and decode a JSON response from the fixed GitHub API host."""
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "verify-action-pins",
    }
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(f"https://api.github.com/{path}", headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.load(response)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        raise RuntimeError(f"GitHub API request failed for {path}: {error}") from error


def parse_action_reference(line: str) -> tuple[str, str, str] | None:
    """Parse a pinned action; explicitly ignore local and Docker container actions."""
    if "uses:" not in line:
        return None
    reference = line.split("uses:", 1)[1].strip()
    if reference.startswith(("./", "docker://")):
        return None
    match = ACTION.match(line)
    if match is None:
        raise ValueError("action must use a full SHA and include its version comment")
    repository, sha, version = match.groups()
    if repository not in ALLOWED_REPOSITORIES:
        raise ValueError(f"unexpected action repository: {repository}")
    return repository, sha, version


def verify_pin(repository: str, sha: str, version: str) -> str | None:
    """Return an error message when a pinned SHA does not match its release tag."""
    expected = tag_commit(repository, version)
    if expected is None:
        return f"tag v{version} not found in {repository}"
    if expected != sha:
        return f"{repository}@{sha} does not match v{version} ({expected})"
    return None


def tag_commit(repository: str, version: str) -> str | None:
    """Resolve a version tag to its commit SHA."""
    if not REPOSITORY.fullmatch(repository) or not VERSION.fullmatch(version):
        raise RuntimeError("invalid action repository or version syntax")
    tag = version if version.startswith("v") else f"v{version}"
    encoded_tag = urllib.parse.quote(tag, safe="")
    encoded_repository = urllib.parse.quote(repository, safe="/")
    ref = api_json(f"repos/{encoded_repository}/git/ref/tags/{encoded_tag}")
    target = ref.get("object", {})
    if target.get("type") == "commit":
        return target.get("sha")
    if target.get("type") != "tag" or not target.get("sha"):
        return None
    annotated = api_json(f"repos/{encoded_repository}/git/tags/{target['sha']}")
    commit = annotated.get("object", {})
    return commit.get("sha") if commit.get("type") == "commit" else None


def main() -> int:
    """Check workflow action SHA pins against their declared version tags."""
    failures: list[str] = []
    checked = 0
    for path in sorted(Path(".github/workflows").glob("*.y*ml")):
        for line_number, line in enumerate(path.read_text().splitlines(), 1):
            if "uses:" not in line:
                continue
            try:
                parsed = parse_action_reference(line)
            except ValueError as error:
                failures.append(f"{path}:{line_number}: {error}")
                continue
            if parsed is None:
                continue
            repository, sha, version = parsed
            checked += 1
            try:
                verification_error = verify_pin(repository, sha, version)
            except RuntimeError as exception:
                failures.append(f"{path}:{line_number}: {exception}")
                continue
            if verification_error:
                failures.append(f"{path}:{line_number}: {verification_error}")

    if checked == 0:
        failures.append("No SHA-pinned GitHub Actions were found to verify.")

    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print(f"Verified {checked} GitHub Actions SHA pins against their version tags.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
