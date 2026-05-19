using Microsoft.UI.Xaml;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using WinRT.Interop;

namespace SaveMe.WinUI.Beta.Services;

public static class ShellFolderService
{
    public static string? PickFolder(Window? owner, string title, string? initialDirectory = null)
    {
        var hwnd = owner is null ? IntPtr.Zero : WindowNative.GetWindowHandle(owner);
        var initialPath = ExistingDirectoryOrDefault(initialDirectory);
        var displayName = Marshal.AllocHGlobal(MaxPath * sizeof(char));
        var initialPathPtr = Marshal.StringToHGlobalUni(initialPath);
        BrowseCallbackProc callback = BrowseCallback;
        var browseInfo = new BROWSEINFO
        {
            hwndOwner = hwnd,
            pszDisplayName = displayName,
            lpszTitle = title,
            ulFlags = BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE | BIF_EDITBOX | BIF_USENEWUI,
            lpfn = Marshal.GetFunctionPointerForDelegate(callback),
            lParam = initialPathPtr,
        };

        try
        {
            var pidl = SHBrowseForFolder(ref browseInfo);
            if (pidl == IntPtr.Zero)
            {
                return null;
            }

            try
            {
                var path = new StringBuilder(MaxPath);
                return SHGetPathFromIDList(pidl, path) ? path.ToString() : null;
            }
            finally
            {
                CoTaskMemFree(pidl);
            }
        }
        finally
        {
            Marshal.FreeHGlobal(displayName);
            Marshal.FreeHGlobal(initialPathPtr);
            GC.KeepAlive(callback);
        }
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

    private static int BrowseCallback(IntPtr hwnd, uint message, IntPtr lParam, IntPtr data)
    {
        if (message == BFFM_INITIALIZED && data != IntPtr.Zero)
        {
            _ = SendMessage(hwnd, BFFM_SETSELECTIONW, new IntPtr(1), data);
        }

        return 0;
    }

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int BrowseCallbackProc(IntPtr hwnd, uint message, IntPtr lParam, IntPtr data);

    private const int MaxPath = 260;
    private const uint BFFM_INITIALIZED = 1;
    private const uint BFFM_SETSELECTIONW = 0x467;
    private const uint BIF_RETURNONLYFSDIRS = 0x00000001;
    private const uint BIF_EDITBOX = 0x00000010;
    private const uint BIF_NEWDIALOGSTYLE = 0x00000040;
    private const uint BIF_USENEWUI = BIF_EDITBOX | BIF_NEWDIALOGSTYLE;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct BROWSEINFO
    {
        public IntPtr hwndOwner;
        public IntPtr pidlRoot;
        public IntPtr pszDisplayName;
        public string lpszTitle;
        public uint ulFlags;
        public IntPtr lpfn;
        public IntPtr lParam;
        public int iImage;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr SHBrowseForFolder(ref BROWSEINFO lpbi);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern bool SHGetPathFromIDList(IntPtr pidl, StringBuilder pszPath);

    [DllImport("ole32.dll")]
    private static extern void CoTaskMemFree(IntPtr pv);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
}
