from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from savestories_windows.updater import WindowsUpdater, WindowsUpdaterError


class WindowsUpdaterTests(unittest.TestCase):
    def test_select_release_asset_pairs_sha256_sidecar(self) -> None:
        updater = WindowsUpdater.__new__(WindowsUpdater)

        asset = updater._select_release_asset(
            [
                {
                    "name": "SaveMe-Windows-Setup-v1.2.3.exe",
                    "browser_download_url": "https://example.test/setup.exe",
                    "size": 123,
                    "digest": "",
                },
                {
                    "name": "SaveMe-Windows-Setup-v1.2.3.exe.sha256",
                    "browser_download_url": "https://example.test/setup.exe.sha256",
                },
            ],
            "v1.2.3",
        )

        self.assertEqual(asset.checksum_url, "https://example.test/setup.exe.sha256")

    def test_verify_digest_accepts_sidecar_checksum(self) -> None:
        updater = WindowsUpdater.__new__(WindowsUpdater)
        with tempfile.TemporaryDirectory() as directory:
            installer = Path(directory) / "setup.exe"
            installer.write_bytes(b"installer")

            updater._verify_digest(
                installer,
                "",
                "9c0d294c05fc1d88d698034609bb81c0c69196327594e4c69d2915c80fd9850c  setup.exe",
            )

    def test_verify_digest_requires_checksum(self) -> None:
        updater = WindowsUpdater.__new__(WindowsUpdater)
        with tempfile.TemporaryDirectory() as directory:
            installer = Path(directory) / "setup.exe"
            installer.write_bytes(b"installer")

            with self.assertRaises(WindowsUpdaterError):
                updater._verify_digest(installer, "", "")

    def test_verify_installer_signature_is_noop_off_windows(self) -> None:
        updater = WindowsUpdater.__new__(WindowsUpdater)
        with tempfile.TemporaryDirectory() as directory:
            installer = Path(directory) / "setup.exe"
            installer.write_bytes(b"installer")

            updater._verify_installer_signature(installer)


if __name__ == "__main__":
    unittest.main()
