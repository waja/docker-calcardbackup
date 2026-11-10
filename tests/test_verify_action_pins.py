"""Unit tests for the GitHub Actions pin verifier."""

import unittest
from unittest import TestCase
from unittest.mock import patch

from scripts.verify_action_pins import (
    parse_action_reference,
    tag_commit,
    verify_pin,
    workflow_action_lines,
)


class ActionReferenceTests(TestCase):
    """Check parsing and verification of pinned workflow action references."""

    def test_parses_full_sha_and_version_comment(self):
        """Accept a SHA-pinned action with a matching version comment."""
        sha = "a" * 40
        self.assertEqual(
            parse_action_reference(f"      - uses: actions/checkout@{sha} # v7.0.1"),
            ("actions/checkout", sha, "7.0.1"),
        )

    def test_parses_quoted_action_reference(self):
        """Accept valid single- or double-quoted action scalars."""
        sha = "a" * 40
        for quote in ('"', "'"):
            with self.subTest(quote=quote):
                prefix = f"      uses: {quote}actions/checkout@"
                action_line = f"{prefix}{sha} # v7.0.1{quote}"
                self.assertEqual(
                    parse_action_reference(action_line),
                    ("actions/checkout", sha, "7.0.1"),
                )

    def test_ignores_uses_text_outside_step_mappings(self):
        """Do not treat comments or run-script content as action references."""
        sha = "a" * 40
        workflow = """jobs:
  build:
    steps:
      - name: Example
        run: |
          echo 'uses: attacker/action@invalid'
          - uses: attacker/action@invalid
        # uses: attacker/action@invalid
      - uses: actions/checkout@""" + sha + """ # v7.0.1
"""
        self.assertEqual(
            list(workflow_action_lines(workflow)),
            [(9, f"uses: actions/checkout@{sha} # v7.0.1")],
        )

    def test_parses_indentationless_and_flow_style_steps(self):
        """Find actions in valid YAML indentationless and flow-style sequences."""
        sha = "b" * 40
        workflow = (
            "jobs:\n"
            "  build:\n"
            "    steps:\n"
            "    - uses: actions/checkout@" + sha + " # v7.0.1\n"
            "  other: { steps: [{ uses: actions/checkout@" + sha + " # v7.0.1 }] }\n"
        )
        found = list(workflow_action_lines(workflow))
        self.assertEqual(len(found), 2)
        self.assertEqual(found[0][1], f"uses: actions/checkout@{sha} # v7.0.1")

    def test_supports_arbitrary_step_indentation(self):
        """Parse valid workflow YAML without assuming a fixed indentation width."""
        sha = "c" * 40
        workflow = (
            "jobs:\n"
            "    build:\n"
            "        steps:\n"
            "            - name: Checkout\n"
            "              uses: actions/checkout@" + sha + " # v7.0.1\n"
        )
        self.assertEqual(
            list(workflow_action_lines(workflow)),
            [(6, f"uses: actions/checkout@{sha} # v7.0.1")],
        )

    def test_rejects_sha_without_version_comment(self):
        """Do not accept a SHA pin that lacks its version comment."""
        sha = "a" * 40
        with self.assertRaises(ValueError):
            parse_action_reference(f"      - uses: actions/checkout@{sha}")

    def test_ignores_local_action_references(self):
        """Treat local action references as an explicit non-SHA case."""
        local_action = "      - uses: ./.github/actions/test"
        self.assertIsNone(parse_action_reference(local_action))

    def test_ignores_docker_container_actions(self):
        """Treat docker:// references as container images, not Git refs."""
        self.assertIsNone(parse_action_reference("      - uses: docker://alpine:3"))

    def test_rejects_malformed_sha(self):
        """Reject action refs that do not use a full 40-character SHA."""
        with self.assertRaises(ValueError):
            parse_action_reference("      - uses: actions/checkout@abc123 # v7.0.1")

    def test_rejects_unexpected_repository(self):
        """Require new action repositories to be reviewed and allowlisted."""
        sha = "a" * 40
        with self.assertRaisesRegex(ValueError, "unexpected action repository"):
            parse_action_reference(f"      - uses: attacker/checkout@{sha} # v7.0.1")

    @patch("scripts.verify_action_pins.tag_commit", return_value="a" * 40)
    def test_accepts_matching_tag_commit(self, mock_tag_commit):
        """Accept a pin when its tag resolves to the same commit."""
        self.assertIsNone(verify_pin("actions/checkout", "a" * 40, "7.0.1"))
        mock_tag_commit.assert_called_once_with("actions/checkout", "7.0.1")

    @patch("scripts.verify_action_pins.tag_commit", return_value="b" * 40)
    def test_rejects_mismatched_sha(self, _tag_commit):
        """Report a mismatch when the version tag resolves elsewhere."""
        error = verify_pin("actions/checkout", "a" * 40, "7.0.1")
        self.assertEqual(
            error,
            f"actions/checkout@{'a' * 40} does not match v7.0.1 ({'b' * 40})",
        )

    @patch("scripts.verify_action_pins.tag_commit", return_value=None)
    def test_rejects_missing_tag(self, _tag_commit):
        """Report a missing version tag instead of accepting the pin."""
        self.assertEqual(
            verify_pin("actions/checkout", "a" * 40, "7.0.1"),
            "tag v7.0.1 not found in actions/checkout",
        )


class ApiRequestTests(TestCase):
    """Check authentication fallback and bounded retries for GitHub API calls."""

    @patch("scripts.verify_action_pins.urllib.request.urlopen")
    @patch.dict("os.environ", {"GITHUB_TOKEN": "scoped-token"})
    def test_retries_public_lookup_without_rejected_token(self, urlopen):
        """Retry an upstream public lookup without an out-of-scope workflow token."""
        from urllib.error import HTTPError
        from io import BytesIO

        denied = HTTPError(
            "https://api.github.com/repos/actions/checkout/git/ref/tags/v7.0.1",
            404,
            "Not Found",
            {},
            BytesIO(b"not found"),
        )
        response = unittest.mock.MagicMock()
        response.__enter__.return_value = response
        response.__exit__.return_value = False
        response.read.return_value = b'{"object":{"type":"commit","sha":"abc"}}'
        response.__enter__.return_value.__class__ = response.__class__
        response.__enter__.return_value.read.return_value = response.read.return_value
        response.__enter__.return_value.__iter__.return_value = iter([])
        response.__enter__.return_value.status = 200
        response.__enter__.return_value.headers = {}
        response.__enter__.return_value.__enter__ = lambda: response.__enter__.return_value
        response.__enter__.return_value.__exit__ = lambda *args: False
        urlopen.side_effect = [denied, response.__enter__.return_value]
        from scripts.verify_action_pins import api_json

        with patch("scripts.verify_action_pins.json.load", return_value={"ok": True}):
            self.assertEqual(api_json("repos/actions/checkout/git/ref/tags/v7.0.1"), {"ok": True})
        first_headers = urlopen.call_args_list[0].args[0].headers
        second_headers = urlopen.call_args_list[1].args[0].headers
        self.assertIn("Bearer scoped-token", first_headers.get("Authorization", ""))
        self.assertNotIn("Authorization", second_headers)


class TagResolutionTests(TestCase):
    """Check dereferencing of annotated Git tags."""

    @patch("scripts.verify_action_pins.api_json")
    def test_resolves_nested_annotated_tags(self, mock_api_json):
        """Follow multiple annotated tag objects until the commit is reached."""
        mock_api_json.side_effect = [
            {"object": {"type": "tag", "sha": "tag-one"}},
            {"object": {"type": "tag", "sha": "tag-two"}},
            {"object": {"type": "commit", "sha": "c" * 40}},
        ]
        self.assertEqual(tag_commit("actions/checkout", "7.0.1"), "c" * 40)
        self.assertEqual(mock_api_json.call_count, 3)


if __name__ == "__main__":
    unittest.main()
