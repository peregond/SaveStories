# SaveMe Windows .beta (WinUI 3)

This is a separate Windows frontend rewrite target based on WinUI 3.

Goals:
- keep current production app (`windows_app`) untouched
- rebuild UI natively for Windows 11
- connect existing backend/worker behavior in later phases
- move Chromium download to post-install bootstrap for smaller installer

Current state:
- standalone WinUI 3 shell with sidebar navigation
- pages: Stories, Queue, Reels, Settings
- explicit `.beta` branding
- persisted theme switch (dark/light) in local settings
- Chromium post-install action in Settings (runs Playwright install)
- Stories page connected to `node_worker` for session check and batch stories download
- Reels page connected to `node_worker` for `download_reels_urls`
- Queue page connected to `node_worker` for `download_profile_batch`
- cancel/timeout support for active worker commands on Stories/Reels/Queue

Build on Windows:
1. Open `SaveStories.WinUI.Beta.sln` in Visual Studio 2022 (17.8+).
2. Ensure "Windows App SDK" workload is installed.
3. Build and run `SaveMe.WinUI.Beta`.

GitHub build:
1. Run workflow `Build WinUI Beta` manually from Actions to get artifact `SaveMe-WinUI-Beta-Setup`.
2. Or push tag `winui-beta-vX.Y.Z` to publish a prerelease with installer `SaveMe-WinUI-Beta-Setup-vX.Y.Z.exe`.

Notes:
- This project is intentionally isolated from the current PySide6 app.
- Migration should be feature-by-feature from stable app to this beta shell.
- If repo root is not auto-detected, set `SAVESTORIES_BETA_REPO_ROOT` to the project root path.
- GitHub Actions beta workflow: `.github/workflows/winui-beta-build.yml`.
