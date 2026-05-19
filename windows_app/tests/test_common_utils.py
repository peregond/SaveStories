from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from savestories_windows.common_utils import (
    batch_status_title,
    normalize_profile_link,
    normalize_reel_link,
    parse_batch_links,
    parse_reel_links,
    snapshot_download_counts,
    suggested_recent_list_title,
)


class CommonUtilsTests(unittest.TestCase):
    def test_normalize_profile_link(self) -> None:
        self.assertEqual(normalize_profile_link(" @alice/ "), "https://www.instagram.com/alice/")
        self.assertEqual(normalize_profile_link("@upngo____"), "https://www.instagram.com/upngo____/")
        self.assertEqual(normalize_profile_link("@*berthi*"), "https://www.instagram.com/berthi/")
        self.assertEqual(
            normalize_profile_link("https://www.instagram.com/bob/"),
            "https://www.instagram.com/bob/",
        )

    def test_parse_batch_links(self) -> None:
        self.assertEqual(
            parse_batch_links("alice, @bob\nhttps://www.instagram.com/carol/"),
            [
                "https://www.instagram.com/alice/",
                "https://www.instagram.com/bob/",
                "https://www.instagram.com/carol/",
            ],
        )
        self.assertEqual(
            parse_batch_links("@timmes198 @smileyboys.comm\n@upngo____;@stoffer__"),
            [
                "https://www.instagram.com/timmes198/",
                "https://www.instagram.com/smileyboys.comm/",
                "https://www.instagram.com/upngo____/",
                "https://www.instagram.com/stoffer__/",
            ],
        )

    def test_parse_reel_links(self) -> None:
        self.assertEqual(
            parse_reel_links(
                "https://www.instagram.com/reel/DMabc123/?utm_source=ig_web_copy_link, https://www.instagram.com/p/CODE456/\ninvalid"
            ),
            [
                "https://www.instagram.com/reel/DMabc123/?utm_source=ig_web_copy_link",
                "https://www.instagram.com/p/CODE456/",
            ],
        )

    def test_normalize_reel_link(self) -> None:
        self.assertEqual(
            normalize_reel_link("https://www.instagram.com/reels/DMabc123/#fragment"),
            "https://www.instagram.com/reels/DMabc123/",
        )
        self.assertEqual(normalize_reel_link("https://www.instagram.com/alice/"), "")

    def test_batch_status_title(self) -> None:
        self.assertEqual(batch_status_title("completed"), "Готово")
        self.assertEqual(batch_status_title("custom"), "custom")

    def test_suggested_recent_list_title(self) -> None:
        self.assertEqual(suggested_recent_list_title(["alice"]), "alice")
        self.assertEqual(suggested_recent_list_title(["alice", "bob", "carol"]), "alice +2")

    def test_snapshot_download_counts(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "profile1").mkdir()
            (root / "profile1" / "story1.jpg").write_bytes(b"jpg")
            (root / "profile1" / "story2.mp4").write_bytes(b"mp4")
            (root / "profile1" / "ignore.txt").write_text("skip", encoding="utf-8")
            (root / "profile2").mkdir()
            files, folders = snapshot_download_counts(root)

        self.assertEqual(files, 2)
        self.assertEqual(folders, 2)


if __name__ == "__main__":
    unittest.main()
