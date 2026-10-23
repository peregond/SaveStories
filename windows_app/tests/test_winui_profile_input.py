from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[2]
WINUI = ROOT / "windows_app_winui_beta/src/SaveStories.WinUI.Beta"


def production_method(path: Path, signature: str) -> str:
    """Compile the production handler body, replacing only its async-void entry point."""
    source = path.read_text(encoding="utf-8")
    start = source.index(signature)
    brace = source.index("{", start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end].replace("private async void", "public async Task", 1)


class WinUIProfileInputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        dotnet = shutil.which("dotnet")
        if not dotnet:
            raise unittest.SkipTest(".NET SDK is needed to execute WinUI profile-input behavior tests")
        sdks = subprocess.run([dotnet, "--list-sdks"], check=True, text=True, capture_output=True).stdout
        majors = [int(match) for match in re.findall(r"^(\d+)\.", sdks, re.MULTILINE) if int(match) >= 8]
        if not majors:
            raise unittest.SkipTest(".NET 8 or newer SDK is required")

        cls.directory = tempfile.TemporaryDirectory(prefix="saveme-winui-input-")
        cls.addClassCleanup(cls.directory.cleanup)
        project = Path(cls.directory.name)
        parser = escape(str(WINUI / "Services/ProfileInputParser.cs"))
        (project / "InputHarness.csproj").write_text(
            f'<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType>'
            f'<TargetFramework>net{max(majors)}.0</TargetFramework><ImplicitUsings>enable</ImplicitUsings>'
            '<Nullable>enable</Nullable><NuGetAudit>false</NuGetAudit></PropertyGroup>'
            f'<ItemGroup><Compile Include="{parser}" Link="ProfileInputParser.cs" /></ItemGroup></Project>',
            encoding="utf-8",
        )
        (project / "NuGet.Config").write_text(
            '<configuration><packageSources><clear /></packageSources></configuration>', encoding="utf-8"
        )
        queue_path = WINUI / "Pages/QueuePage.xaml.cs"
        stories_path = WINUI / "Pages/StoriesPage.xaml.cs"
        queue_run = production_method(queue_path, "private async void OnRunQueueClick(")
        stories_run = production_method(stories_path, "private async void OnDownloadClick(")
        queue_add = production_method(queue_path, "private int AddQueueItems(")
        stories_add = production_method(stories_path, "private int AddQueueItems(")
        program = r'''
using System.Collections.ObjectModel;
using System.Text.Json;
using SaveMe.WinUI.Beta.Services;

public static class Program {
    public static async Task Main() {
        var queue = new QueueHarness();
        queue.Queue.Add("https://www.instagram.com/alice/");
        queue.Input.Text = "@bob https://www.instagram.com/stories/carol/123/ @ALICE";
        await queue.OnRunQueueClick(new object(), new());
        var stories = new StoriesHarness();
        stories.Queue.Add("https://www.instagram.com/alice/");
        stories.Input.Text = "@bob https://www.instagram.com/stories/carol/123/ @ALICE";
        await stories.OnDownloadClick(new object(), new());
        var notion = new StoriesHarness();
        notion.Queue.Add("https://www.instagram.com/old/");
        notion.NotionInfluencerToggle.IsOn = true;
        notion.Input.Text = "@bob @NOTION";
        await notion.OnDownloadClick(new object(), new());
        Console.WriteLine("RESULT:" + JsonSerializer.Serialize(new {
            StoryProfiles = ProfileInputParser.ParseProfiles("https://www.instagram.com/stories/alice/123/ https://instagram.com/stories/bob/456/?x=1 @ALICE"),
            InvalidProfiles = ProfileInputParser.ParseProfiles("https://instagram.com/stories/highlights/123/ https://instagram.com/reel/CODE/ https://instagram.com/p/CODE/ https://instagram.com/accounts/login/ https://instagram.com/stories/ https://notinstagram.com/alice/ https://instagram.com.evil.test/bob/"),
            RegularProfiles = ProfileInputParser.ParseProfiles("alice, @*berthi*; www.instagram.com/carol/?x=1 @ALICE"),
            QueueRequest = queue.Request?.Urls, QueueInput = queue.Input.Text,
            StoriesRequest = stories.Request?.Urls, StoriesInput = stories.Input.Text,
            NotionRequest = notion.Request?.Urls,
        }));
    }
}
public sealed class TextField { public string Text { get; set; } = ""; }
public sealed class Toggle { public bool IsOn { get; set; } }
public sealed class WorkerRequest {
    public string Command { get; set; } = "";
    public List<string> Urls { get; set; } = new();
    public string OutputDirectory { get; set; } = "";
    public bool Headless { get; set; }
    public string MediaFilter { get; set; } = "";
}
public sealed class WorkerBridgeService {
    public static WorkerBridgeService Current { get; } = new();
    public string GetDefaultDownloadsDirectory() => "test-downloads";
}
public sealed class QueueHarness {
    private readonly ObservableCollection<string> _queue = new();
    private bool _isRunning = false;
    private TextField QueueInputTextBox = new();
    private TextField QueueStatusTitleText = new();
    private TextField QueueStatusDetailText = new();
    public ObservableCollection<string> Queue => _queue;
    public TextField Input => QueueInputTextBox;
    public WorkerRequest? Request { get; private set; }
    private void RefreshQueueSummary() {}
    private Task RunWorkerCommandAsync(WorkerRequest request, string message) { Request = request; return Task.CompletedTask; }
    __QUEUE_RUN__
    __QUEUE_ADD__
}
public sealed class StoriesHarness {
    private readonly ObservableCollection<string> _queue = new();
    private bool _isRunning = false;
    private string _outputDirectory = "test-downloads";
    private TextField ProfilesInputTextBox = new();
    private TextField StatusTitleText = new();
    private TextField StatusDetailText = new();
    public Toggle NotionInfluencerToggle = new();
    public ObservableCollection<string> Queue => _queue;
    public TextField Input => ProfilesInputTextBox;
    public WorkerRequest? Request { get; private set; }
    private void RefreshQueueSummary() {}
    private void UpdateProfilesInputState() {}
    private bool IsHeadlessMode() => true;
    private string GetMediaFilter() => "video_only";
    private Task<bool> RefreshNotionInfluencersAsync(bool replaceQueue) {
        if (replaceQueue) _queue.Clear();
        _queue.Add("https://www.instagram.com/notion/");
        return Task.FromResult(true);
    }
    private Task RunWorkerCommandAsync(WorkerRequest request, string message) { Request = request; return Task.CompletedTask; }
    __STORIES_RUN__
    __STORIES_ADD__
}
namespace Microsoft.UI.Xaml { public sealed class RoutedEventArgs {} }
'''
        for marker, method in {
            "__QUEUE_RUN__": queue_run,
            "__QUEUE_ADD__": queue_add,
            "__STORIES_RUN__": stories_run,
            "__STORIES_ADD__": stories_add,
        }.items():
            program = program.replace(marker, method)
        (project / "Program.cs").write_text(program, encoding="utf-8")
        environment = {
            **os.environ,
            "DOTNET_CLI_HOME": str(project / "cli-home"),
            "DOTNET_SKIP_FIRST_TIME_EXPERIENCE": "1",
            "DOTNET_CLI_TELEMETRY_OPTOUT": "1",
            "DOTNET_NOLOGO": "1",
        }
        result = subprocess.run(
            [dotnet, "run", "--project", str(project / "InputHarness.csproj"), "--verbosity", "quiet"],
            text=True, capture_output=True, env=environment, timeout=120,
        )
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        cls.results = json.loads(next(line[7:] for line in result.stdout.splitlines() if line.startswith("RESULT:")))

    def test_story_urls_keep_each_influencer_and_deduplicate_handles(self) -> None:
        self.assertEqual(self.results["StoryProfiles"], [
            "https://www.instagram.com/alice/", "https://www.instagram.com/bob/",
        ])

    def test_non_profile_routes_and_lookalike_hosts_are_not_influencers(self) -> None:
        self.assertEqual(self.results["InvalidProfiles"], [])

    def test_existing_profile_input_formats_are_preserved(self) -> None:
        self.assertEqual(self.results["RegularProfiles"], [
            "https://www.instagram.com/alice/", "https://www.instagram.com/berthi/", "https://www.instagram.com/carol/",
        ])

    def test_queue_download_includes_pending_text_when_queue_already_has_profiles(self) -> None:
        self.assertEqual(self.results["QueueRequest"], [
            "https://www.instagram.com/alice/", "https://www.instagram.com/bob/", "https://www.instagram.com/carol/",
        ])
        self.assertEqual(self.results["QueueInput"], "")

    def test_stories_download_includes_pending_text_when_queue_already_has_profiles(self) -> None:
        self.assertEqual(self.results["StoriesRequest"], [
            "https://www.instagram.com/alice/", "https://www.instagram.com/bob/", "https://www.instagram.com/carol/",
        ])
        self.assertEqual(self.results["StoriesInput"], "")

    def test_manual_profiles_merge_with_refreshed_notion_queue(self) -> None:
        self.assertEqual(self.results["NotionRequest"], [
            "https://www.instagram.com/notion/", "https://www.instagram.com/bob/",
        ])


if __name__ == "__main__":
    unittest.main()
