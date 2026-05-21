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
        self.assertIn("FindCleanupCandidateSubfolders", page)
        self.assertIn("IsIgnorableFilesystemEntry", page)
        self.assertIn("Directory.Delete(folder, recursive: true)", page)

    def test_first_run_onboarding_shows_runtime_stages(self) -> None:
        main_window = read("windows_app_winui_beta/src/SaveStories.WinUI.Beta/MainWindow.xaml.cs")

        self.assertIn("RuntimeSetupStage", main_window)
        self.assertIn("CreateRuntimeStageRows", main_window)
        self.assertIn("BuildRuntimeInstallErrorMessage", main_window)
        for label in ("Node 24 LTS", "Worker", "Playwright", "Chromium", "Готово"):
            self.assertIn(label, main_window)


if __name__ == "__main__":
    unittest.main()
