using Microsoft.UI.Xaml;
using System.Diagnostics;
using Forms = System.Windows.Forms;
using WinRT.Interop;

namespace SaveMe.WinUI.Beta.Services;

public static class ShellFolderService
{
    public static string? PickFolder(Window? owner, string title, string? initialDirectory = null)
    {
        using var dialog = new Forms.FolderBrowserDialog
        {
            Description = title,
            UseDescriptionForTitle = true,
            ShowNewFolderButton = true,
            InitialDirectory = ExistingDirectoryOrDefault(initialDirectory),
        };

        var result = owner is null
            ? dialog.ShowDialog()
            : dialog.ShowDialog(new WindowHandleOwner(WindowNative.GetWindowHandle(owner)));

        return result == Forms.DialogResult.OK && !string.IsNullOrWhiteSpace(dialog.SelectedPath)
            ? dialog.SelectedPath
            : null;
    }

    public static void OpenFolder(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        Directory.CreateDirectory(path);
        Process.Start(new ProcessStartInfo
        {
            FileName = path,
            UseShellExecute = true,
        });
    }

    private static string ExistingDirectoryOrDefault(string? path)
    {
        if (!string.IsNullOrWhiteSpace(path) && Directory.Exists(path))
        {
            return path;
        }

        var downloads = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            "Downloads");
        return Directory.Exists(downloads)
            ? downloads
            : Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
    }

    private sealed class WindowHandleOwner(nint handle) : Forms.IWin32Window
    {
        public IntPtr Handle { get; } = handle;
    }
}
