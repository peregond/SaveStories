from __future__ import annotations

import contextlib
import importlib.util
import io
import plistlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "macos_bundle.py"
SPEC = importlib.util.spec_from_file_location("macos_bundle", SCRIPT)
bundle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bundle)


class MacOSBundleTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.app = Path(self.directory.name) / "SaveMe.app"
        self.plist = self.app / "Contents/Info.plist"
        self.plist.parent.mkdir(parents=True)
        self.info = {
            "CFBundleExecutable": "SaveMe",
            "CFBundleIdentifier": "local.saveme.preview",
            "CFBundleIconName": "SaveMe",
            "LSMinimumSystemVersion": "99.0",
            "DTSDKName": "macosx99.0",
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": "test-key",
            "SUEnableAutomaticChecks": True,
            "SUAutomaticallyUpdate": True,
        }
        self.plist.write_bytes(plistlib.dumps(self.info))
        for relative in (
            "MacOS/SaveMe", "Helpers/SaveMeMediaMuxer", "Resources/SaveMe.icns",
            "Resources/SaveMe_SaveMe.bundle/bootstrap_worker.sh",
            "Resources/SaveMe_SaveMe.bundle/google_drive_copy_link.applescript",
            "Resources/SaveMe_SaveMe.bundle/update_config.json",
            "Resources/SaveMe_SaveMe.bundle/worker/bridge.py",
            "Frameworks/Sparkle.framework/Sparkle",
            "SharedSupport/node_worker/package.json",
            "SharedSupport/node_worker/package-lock.json",
            "SharedSupport/node_worker/bridge.mjs",
        ):
            target = self.app / "Contents" / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.touch()

    def tool_output(self, *command):
        if command[:3] == ("xcrun", "vtool", "-show-build"):
            minimum = "14.5" if command[-1].endswith("SaveMeMediaMuxer") else "14.0"
            return f" platform MACOS\n minos {minimum}\n sdk 26.5\n"
        if command[:2] == ("lipo", "-archs"):
            return "arm64 x86_64"
        if command[:2] == ("codesign", "--verify"):
            return ""
        self.fail(f"Unexpected command: {command}")

    def invoke(self, *arguments):
        with patch.object(bundle, "run", side_effect=self.tool_output), \
             patch("sys.argv", [str(SCRIPT), *arguments, "--app", str(self.app)]), \
             contextlib.redirect_stdout(io.StringIO()):
            return bundle.main()

    def test_xcode27_structured_resource_bundle(self):
        root = self.app / "Contents/Resources/SaveMe_SaveMe.bundle"
        structured = root / "Contents/Resources"
        children = list(root.iterdir())
        structured.mkdir(parents=True)
        for child in children:
            child.rename(structured / child.name)
        self.assertEqual(self.invoke("stamp", "--preview"), 0)
        (structured / "bootstrap_worker.sh").unlink()
        with self.assertRaises(ValueError):
            self.invoke("verify")

    def test_preview_uses_binary_versions_and_removes_release_update_configuration(self):
        self.assertEqual(self.invoke("stamp", "--preview"), 0)
        info = plistlib.loads(self.plist.read_bytes())
        self.assertEqual(info["LSMinimumSystemVersion"], "14.5")
        self.assertEqual(info["DTSDKName"], "macosx26.5")
        self.assertEqual(info["CFBundleIdentifier"], "local.saveme.preview")
        self.assertEqual(info["CFBundleDisplayName"], "SaveMe Preview")
        self.assertFalse(info["SUEnableAutomaticChecks"])
        self.assertFalse(info["SUAutomaticallyUpdate"])
        self.assertNotIn("SUFeedURL", info)
        self.assertNotIn("SUPublicEDKey", info)
        self.assertNotIn("CFBundleIconName", info)

    def test_missing_worker_resource_is_rejected_before_signing(self):
        resource = self.app / "Contents/Resources/SaveMe_SaveMe.bundle/bootstrap_worker.sh"
        resource.unlink()
        with self.assertRaisesRegex(ValueError, "Incomplete app bundle.*bootstrap_worker.sh"):
            self.invoke("stamp")

    def test_new_sdk_requirement_rejects_older_binaries(self):
        with self.assertRaisesRegex(ValueError, "built with SDK 26.5"):
            self.invoke("stamp", "--require-sdk", "27")

    def test_stale_plist_versions_fail_verification(self):
        with self.assertRaisesRegex(ValueError, "LSMinimumSystemVersion"):
            self.invoke("verify")
        self.invoke("stamp")
        info = plistlib.loads(self.plist.read_bytes())
        info["DTSDKName"] = "macosx27.0"
        self.plist.write_bytes(plistlib.dumps(info))
        with self.assertRaisesRegex(ValueError, "DTSDKName"):
            self.invoke("verify")

    def test_helper_without_all_app_architectures_is_rejected(self):
        original_tool = self.tool_output

        def missing_architecture(*command):
            if command[:2] == ("lipo", "-archs") and command[-1].endswith("SaveMeMediaMuxer"):
                return "arm64"
            return original_tool(*command)

        with patch.object(self, "tool_output", side_effect=missing_architecture):
            with self.assertRaisesRegex(ValueError, "missing an app architecture"):
                self.invoke("stamp")

    def test_universal_binary_checks_oldest_sdk_and_highest_minimum(self):
        output = "minos 14.0\nsdk 27.0\nminos 14.5\nsdk 26.5\n"
        self.assertEqual(bundle.build_versions(output), ("14.5", "26.5"))
        with self.assertRaisesRegex(ValueError, "Missing macOS build-version"):
            bundle.build_versions("minos 14.0\n")


if __name__ == "__main__":
    unittest.main()
