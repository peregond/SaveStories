from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class WinUILightweightRuntimeTests(unittest.TestCase):
    def test_windows_release_workflows_do_not_bundle_node_runtime(self) -> None:
        for workflow in (
            ".github/workflows/release-assets.yml",
            ".github/workflows/winui-beta-build.yml",
        ):
            with self.subTest(workflow=workflow):
                text = read(workflow)
                self.assertNotIn("Bundle Node.js runtime", text)
                self.assertNotIn("dist\\winui\\runtime\\node", text)
                self.assertNotIn("node-v24.11.0-win-x64.zip", text)

    def test_winui_runtime_installs_into_user_local_app_data(self) -> None:
        resolver = read(
            "windows_app_winui_beta/src/SaveStories.WinUI.Beta/Services/NodeRuntimeResolver.cs"
        )
        bootstrap = read(
            "windows_app_winui_beta/src/SaveStories.WinUI.Beta/Services/ChromiumBootstrapService.cs"
        )

        self.assertIn("Environment.SpecialFolder.LocalApplicationData", resolver)
        self.assertIn('Path.Combine(root, "SaveMe", "worker")', resolver)
        self.assertIn("InstalledNodeExecutablePath", resolver)
        self.assertIn("InstalledNpmCliPath", resolver)
        self.assertIn("EnsureNodeRuntimeInstalledAsync", bootstrap)
        self.assertIn("https://nodejs.org/dist/", bootstrap)
        self.assertIn('"node"', bootstrap)
        self.assertIn('"node_modules"', bootstrap)

    def test_winui_worker_prefers_downloaded_worker_copy(self) -> None:
        bridge = read(
            "windows_app_winui_beta/src/SaveStories.WinUI.Beta/Services/WorkerBridgeService.cs"
        )

        self.assertIn("ResolveWorkerScript", bridge)
        self.assertIn("NodeRuntimeResolver.WorkerRoot()", bridge)
        self.assertIn("Path.GetDirectoryName(workerScript)", bridge)

    def test_winui_worker_extracts_json_from_noisy_stdout(self) -> None:
        bridge = read(
            "windows_app_winui_beta/src/SaveStories.WinUI.Beta/Services/WorkerBridgeService.cs"
        )

        self.assertIn("ExtractFirstJsonObject", bridge)
        self.assertIn("JsonSerializer.Deserialize<WorkerResponse>(stdoutJson)", bridge)
        self.assertIn("worker_stdout_tail=", bridge)
        self.assertNotIn("JsonSerializer.Deserialize<WorkerResponse>(stdout)", bridge)

    def test_winui_stories_updates_result_from_worker_progress(self) -> None:
        page = read("windows_app_winui_beta/src/SaveStories.WinUI.Beta/Pages/StoriesPage.xaml.cs")
        bridge = read(
            "windows_app_winui_beta/src/SaveStories.WinUI.Beta/Services/WorkerBridgeService.cs"
        )

        self.assertIn("IProgress<string>? progress", bridge)
        self.assertIn("progress?.Report", bridge)
        self.assertIn("HandleWorkerProgress", page)
        self.assertIn("batch_slot_", page)
        self.assertIn("Обработано: {_liveProcessedProfiles}/{_queue.Count}", page)

    def test_winui_stories_batch_timeout_scales_with_queue_size(self) -> None:
        page = read("windows_app_winui_beta/src/SaveStories.WinUI.Beta/Pages/StoriesPage.xaml.cs")

        self.assertIn("BuildWorkerTimeout", page)
        self.assertIn('request.Command, "download_profile_batch"', page)
        self.assertIn("request.Urls.Count", page)
        self.assertIn("Math.Clamp(20 + profileCount * minutesPerProfile, 30, 720)", page)
        self.assertIn("timeout: workerTimeout", page)
        self.assertIn("batch_timeout_minutes=", page)

    def test_winui_stories_tracks_live_downloaded_files_and_folders(self) -> None:
        page = read("windows_app_winui_beta/src/SaveStories.WinUI.Beta/Pages/StoriesPage.xaml.cs")
        xaml = read("windows_app_winui_beta/src/SaveStories.WinUI.Beta/Pages/StoriesPage.xaml")

        self.assertIn("LiveDownloadStatsText", xaml)
        self.assertIn("ResetLiveDownloadStatsBaseline", page)
        self.assertIn("RefreshLiveDownloadStats", page)
        self.assertIn("SnapshotOutputDirectory", page)
        self.assertIn("SupportedMediaExtensions", page)
        self.assertIn("_liveStatsTimer", page)
        self.assertIn("Файлов загружено:", page)

    def test_winui_stories_persists_output_directory_and_offers_empty_cleanup(self) -> None:
        page = read("windows_app_winui_beta/src/SaveStories.WinUI.Beta/Pages/StoriesPage.xaml.cs")
        settings = read(
            "windows_app_winui_beta/src/SaveStories.WinUI.Beta/Services/BetaSettingsStore.cs"
        )

        self.assertIn("StoriesOutputDirectory", settings)
        self.assertIn("SetStoriesOutputDirectory", settings)
        self.assertIn("BetaSettingsStore.Current.StoriesOutputDirectory", page)
        self.assertIn("BetaSettingsStore.Current.SetStoriesOutputDirectory", page)
        self.assertIn("OfferEmptyFolderCleanupAsync", page)
        self.assertIn("FindEmptyStoryFolders", page)
        self.assertIn("IsProtectedTransferDirectory", page)
        self.assertIn("IsIgnorableFilesystemEntry", page)
        self.assertIn("Удалить пустые папки?", page)

    def test_winui_sorting_has_independent_empty_folder_cleanup(self) -> None:
        page = read("windows_app_winui_beta/src/SaveStories.WinUI.Beta/Pages/SortingPage.xaml.cs")
        xaml = read("windows_app_winui_beta/src/SaveStories.WinUI.Beta/Pages/SortingPage.xaml")
        settings = read(
            "windows_app_winui_beta/src/SaveStories.WinUI.Beta/Services/BetaSettingsStore.cs"
        )

        self.assertIn("EmptyFolderCleanupDirectory", settings)
        self.assertIn("SetEmptyFolderCleanupDirectory", settings)
        self.assertIn("0. УДАЛИТЬ ПУСТЫЕ ПАПКИ", xaml)
        self.assertIn("OnDeleteEmptyFoldersClick", page)
        self.assertIn("EmptyFolderCleanupStatusText", xaml)
        self.assertIn("FindDeletableEmptySubfolders", page)
        self.assertIn("IsEffectivelyEmptyDirectoryAfterDeletingKnownEmptyChildren", page)
        self.assertIn("IsIgnorableFilesystemEntry", page)
        self.assertIn("IsProtectedTransferDirectory", page)
        self.assertIn("На перенос", page)
        self.assertIn("Directory.Delete(folder, recursive: true)", page)

    def test_winui_sorting_has_google_drive_link_digest_buttons(self) -> None:
        page = read("windows_app_winui_beta/src/SaveStories.WinUI.Beta/Pages/SortingPage.xaml.cs")
        xaml = read("windows_app_winui_beta/src/SaveStories.WinUI.Beta/Pages/SortingPage.xaml")
        service = read("windows_app_winui_beta/src/SaveStories.WinUI.Beta/Services/SortingService.cs")
        exporter = read("windows_app_winui_beta/src/SaveStories.WinUI.Beta/Services/GoogleDriveLinkExporter.cs")

        self.assertIn("5. СКОПИРУЙ ГОТОВЫЙ РЕЗУЛЬТАТ", xaml)
        self.assertIn("Скопировать список", xaml)
        self.assertIn("Скопировать ссылки", xaml)
        self.assertIn("OnCopyLinksClick", page)
        self.assertIn("BuildPostProcessedReport", service)
        self.assertIn("BuildGoogleDriveDigest", service)
        self.assertIn("com.google.drivefs.item-id", exporter)
        self.assertIn("https://drive.google.com/open?id=", exporter)

    def test_winui_sorting_transfer_matches_macos_visible_file_rules(self) -> None:
        service = read("windows_app_winui_beta/src/SaveStories.WinUI.Beta/Services/SortingService.cs")

        self.assertIn(".Where(IsVisibleDirectory)", service)
        self.assertIn(".Where(IsVisibleRegularFile)", service)
        self.assertIn("attributes.HasFlag(FileAttributes.Hidden)", service)
        self.assertIn("attributes.HasFlag(FileAttributes.System)", service)
        self.assertIn("ReportHeader", service)

    def test_first_run_onboarding_shows_runtime_stages(self) -> None:
        main_window = read("windows_app_winui_beta/src/SaveStories.WinUI.Beta/MainWindow.xaml.cs")

        self.assertIn("RuntimeSetupStage", main_window)
        self.assertIn("CreateRuntimeStageRows", main_window)
        self.assertIn("BuildRuntimeInstallErrorMessage", main_window)
        for label in ("Node 24 LTS", "Worker", "Playwright", "Chromium", "Готово"):
            self.assertIn(label, main_window)


if __name__ == "__main__":
    unittest.main()
