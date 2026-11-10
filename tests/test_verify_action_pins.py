"""Unit tests for the GitHub Actions pin verifier."""

import unittest
from unittest import TestCase
from unittest.mock import patch

from scripts.verify_action_pins import (
    ACTION,
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
        match = ACTION.match(f"      - uses: actions/checkout@{sha} # v7.0.1")
        self.assertIsNotNone(match)
        self.assertEqual(
            match.groups(),
            ("actions/checkout", sha, "7.0.1"),
        )

    def test_parses_quoted_action_reference(self):
        """Accept valid single- or double-quoted action scalars."""
        sha = "a" * 40
        for quote in ('"', "'"):
            with self.subTest(quote=quote):
                self.assertEqual(
                    parse_action_reference(
                        f"      uses: {quote}actions/checkout@{sha} # v7.0.1{quote}"
                    ),
                    ("actions/checkout", sha, "7.0.1"),
                )

    def test_ignores_uses_text_outside_step_mappings(self):
        """Do not treat comments or run-script content as action references."""
        lines = [
            "jobs:",
            "  build:",
            "    steps:",
            "      - name: Example",
            "        run: |",
            "          echo 'uses: attacker/action@invalid'",
            "          - uses: attacker/action@invalid",
            "        # uses: attacker/action@invalid",
            "      - uses: actions/checkout@" + "a" * 40 + " # v7.0.1",
        ]
        self.assertEqual(
            list(workflow_action_lines(lines)),
            [(9, "uses: actions/checkout@" + "a" * 40 + " # v7.0.1")],
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
    def test_accepts_matching_tag_commit(self, tag_commit):
        """Accept a pin when its tag resolves to the same commit."""
        self.assertIsNone(verify_pin("actions/checkout", "a" * 40, "7.0.1"))
        tag_commit.assert_called_once_with("actions/checkout", "7.0.1")

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
