"""Verify that workflow action SHA pins match their declared version tags."""

from __future__ import annotations

import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import yaml

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
    """Fetch public GitHub API JSON with auth fallback and bounded retries."""
    url = f"https://api.github.com/{path}"
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "verify-action-pins",
    }
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"

    for attempt in range(4):
        request = urllib.request.Request(url, headers=headers)
        delay = 0
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            body = error.read().decode("utf-8", errors="replace")
            error.close()
            auth_denied = error.code in (401, 404)
            if error.code == 403 and "Resource not accessible" in body:
                auth_denied = True
            if token and auth_denied:
                headers.pop("Authorization", None)
                token = None
                continue
            if error.code not in (429, 500, 502, 503, 504) or attempt == 3:
                message = (
                    f"GitHub API request failed for {path}: "
                    f"HTTP {error.code}: {body}"
                )
                raise RuntimeError(message) from error
            retry_after = error.headers.get("Retry-After")
            if retry_after and retry_after.isdigit():
                delay = min(int(retry_after), 30)
            else:
                delay = 2**attempt
        except (urllib.error.URLError, TimeoutError) as error:
            if attempt == 3:
                message = f"GitHub API request failed for {path}: {error}"
                raise RuntimeError(message) from error
            delay = 2**attempt
        except json.JSONDecodeError as error:
            message = f"GitHub API returned invalid JSON for {path}: {error}"
            raise RuntimeError(message) from error
        time.sleep(delay)

    raise RuntimeError(f"GitHub API request exhausted retries for {path}")


def parse_action_reference(line: str) -> tuple[str, str, str] | None:
    """Parse a pinned action; explicitly ignore local and Docker container actions."""
    match = re.match(r"^\s*(?:-\s*)?uses:\s*(.*?)\s*$", line)
    if match is None:
        return None

    reference = match.group(1).strip()
    if reference.startswith(('"', "'")):
        quote = reference[0]
        end = reference.find(quote, 1)
        trailing = reference[end + 1 :].strip()
        if end < 0 or (trailing and not trailing.startswith("#")):
            raise ValueError("malformed quoted action reference")
        reference = reference[1:end] + (f" {trailing}" if trailing else "")
    if reference.startswith(("./", "docker://")):
        return None
    action_match = ACTION.match(f"uses: {reference}")
    if action_match is None:
        raise ValueError("action must use a full SHA and include its version comment")
    repository, sha, version = action_match.groups()
    if repository not in ALLOWED_REPOSITORIES:
        raise ValueError(f"unexpected action repository: {repository}")
    return repository, sha, version


def mapping_value(mapping, key_name):
    """Return a YAML mapping value for a scalar key."""
    for key, value in mapping.value:
        if isinstance(key, yaml.ScalarNode) and key.value == key_name:
            return value
    return None


def workflow_action_lines(workflow_text: str):
    """Yield action references from YAML step mappings, preserving line numbers."""
    document = yaml.compose(workflow_text)
    if not isinstance(document, yaml.MappingNode):
        return

    raw_lines = workflow_text.splitlines()
    jobs = mapping_value(document, "jobs")
    if not isinstance(jobs, yaml.MappingNode):
        return

    for _, job in jobs.value:
        if not isinstance(job, yaml.MappingNode):
            continue
        steps = mapping_value(job, "steps")
        if not isinstance(steps, yaml.SequenceNode):
            continue
        for step in steps.value:
            if not isinstance(step, yaml.MappingNode):
                continue
            for key, value in step.value:
                if not isinstance(key, yaml.ScalarNode) or key.value != "uses":
                    continue
                if not isinstance(value, yaml.ScalarNode):
                    continue
                line_number = value.start_mark.line + 1
                reference = value.value
                raw_line = raw_lines[line_number - 1]
                comment = re.search(
                    r"\s+#\s*v[0-9A-Za-z][0-9A-Za-z._+-]*\s*$",
                    raw_line,
                )
                if comment and "#" not in reference:
                    reference = f"{reference}{comment.group(0)}"
                yield line_number, f"uses: {reference}"


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
    seen: set[str] = set()
    while target.get("type") == "tag" and target.get("sha"):
        tag_sha = target["sha"]
        if tag_sha in seen:
            message = f"tag cycle detected: {repository} v{version}"
            raise RuntimeError(message)
        seen.add(tag_sha)
        annotated = api_json(f"repos/{encoded_repository}/git/tags/{tag_sha}")
        target = annotated.get("object", {})
    return target.get("sha") if target.get("type") == "commit" else None


def main() -> int:
    """Check workflow action SHA pins against their declared version tags."""
    failures: list[str] = []
    checked = 0
    for path in sorted(Path(".github/workflows").glob("*.y*ml")):
        for line_number, line in workflow_action_lines(path.read_text()):
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
