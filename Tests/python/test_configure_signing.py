from argparse import ArgumentTypeError
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Scripts"))

import configure_signing as signing


class ConfigureSigningTests(unittest.TestCase):
    def setUp(self):
        self.project = (ROOT / "project.yml").read_text(encoding="utf-8")
        self.app_group = (ROOT / "Shared/AppGroup.swift").read_text(encoding="utf-8")

    def test_rejects_example_values(self):
        for value in ("YOURTEAMID", "ABCDE12345"):
            with self.subTest(value=value), self.assertRaises(ArgumentTypeError):
                signing.validate_team_id(value)
        for value in ("com.example.noisegate", "com.yourname.noisegate"):
            with self.subTest(value=value), self.assertRaises(ArgumentTypeError):
                signing.validate_app_bundle_id(value)

    def test_rejects_malformed_identifiers(self):
        for value in (
            "com-foo",
            "com.-foo",
            "com.foo-",
            "Com.Foo.NoiseGate",
            "group.com.foo.noisegate",
        ):
            with self.subTest(value=value), self.assertRaises(ArgumentTypeError):
                signing.validate_app_bundle_id(value)

    def test_derives_every_identifier_and_is_idempotent(self):
        app_bundle_id = "com.bfvaseghi.noisegate"
        configured = signing.configured_project(
            self.project,
            "Z9Y8X7W6V5",
            app_bundle_id,
        )
        for target, suffix in signing.TARGET_SUFFIXES.items():
            with self.subTest(target=target):
                self.assertIn(
                    f"PRODUCT_BUNDLE_IDENTIFIER: {app_bundle_id}{suffix}",
                    configured,
                )
        self.assertEqual(configured.count(f"- group.{app_bundle_id}"), 6)
        self.assertIn('DEVELOPMENT_TEAM: "Z9Y8X7W6V5"', configured)
        self.assertEqual(
            signing.configured_project(configured, "Z9Y8X7W6V5", app_bundle_id),
            configured,
        )

        group = signing.configured_app_group(self.app_group, app_bundle_id)
        self.assertIn(f'static let id = "group.{app_bundle_id}"', group)
        self.assertEqual(signing.configured_app_group(group, app_bundle_id), group)

    def test_refuses_incomplete_project(self):
        missing_target = self.project.replace(
            "        PRODUCT_BUNDLE_IDENTIFIER: com.example.noisegate.report\n",
            "",
        )
        with self.assertRaises(ValueError):
            signing.configured_project(
                missing_target,
                "Z9Y8X7W6V5",
                "com.bfvaseghi.noisegate",
            )

        missing_group = self.project.replace(
            "          - group.com.example.noisegate\n",
            "",
            1,
        )
        with self.assertRaises(ValueError):
            signing.configured_project(
                missing_group,
                "Z9Y8X7W6V5",
                "com.bfvaseghi.noisegate",
            )


if __name__ == "__main__":
    unittest.main()
