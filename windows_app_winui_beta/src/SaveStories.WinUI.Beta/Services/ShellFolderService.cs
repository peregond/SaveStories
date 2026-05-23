using Microsoft.UI.Xaml;
using System.Diagnostics;
using System.Runtime.InteropServices;
using WinRT.Interop;

namespace SaveMe.WinUI.Beta.Services;

public static class ShellFolderService
{
    public static string? PickFolder(Window? owner, string title, string? initialDirectory = null)
    {
        var hwnd = owner is null ? IntPtr.Zero : WindowNative.GetWindowHandle(owner);
        var dialog = CreateFileOpenDialog();
        var initialPath = ExistingDirectoryOrDefault(initialDirectory);

        dialog.GetOptions(out var options);
        dialog.SetOptions(options | FileOpenOptions.PickFolders | FileOpenOptions.ForceFilesystem | FileOpenOptions.PathMustExist);
        dialog.SetTitle(title);

        if (TryCreateShellItem(initialPath, out var initialFolder) && initialFolder is not null)
        {
            dialog.SetFolder(initialFolder);
        }

        var result = dialog.Show(hwnd);
        if (result == HResultCancelled)
        {
            return null;
        }

        Marshal.ThrowExceptionForHR(result);
        dialog.GetResult(out var item);
        item.GetDisplayName(ShellItemDisplayName.FileSystemPath, out var pathPointer);

        try
        {
            return Marshal.PtrToStringUni(pathPointer);
        }
        finally
        {
            Marshal.FreeCoTaskMem(pathPointer);
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

    private static bool TryCreateShellItem(string path, out IShellItem? shellItem)
    {
        shellItem = null;
        if (string.IsNullOrWhiteSpace(path) || !Directory.Exists(path))
        {
            return false;
        }

        var hr = SHCreateItemFromParsingName(path, IntPtr.Zero, typeof(IShellItem).GUID, out shellItem);
        return hr >= 0 && shellItem is not null;
    }

    private static IFileOpenDialog CreateFileOpenDialog()
    {
        var dialogType = Type.GetTypeFromCLSID(FileOpenDialogClsid, throwOnError: true);
        return (IFileOpenDialog)Activator.CreateInstance(dialogType!)!;
    }

    private const int HResultCancelled = unchecked((int)0x800704C7);
    private static readonly Guid FileOpenDialogClsid = new("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7");

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
    private static extern int SHCreateItemFromParsingName(
        string pszPath,
        IntPtr pbc,
        [MarshalAs(UnmanagedType.LPStruct)] Guid riid,
        [MarshalAs(UnmanagedType.Interface)] out IShellItem? ppv);

    [ComImport]
    [Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItem
    {
        void BindToHandler(IntPtr pbc, [MarshalAs(UnmanagedType.LPStruct)] Guid bhid, [MarshalAs(UnmanagedType.LPStruct)] Guid riid, out IntPtr ppv);
        void GetParent(out IShellItem ppsi);
        void GetDisplayName(ShellItemDisplayName sigdnName, out IntPtr ppszName);
        void GetAttributes(uint sfgaoMask, out uint psfgaoAttribs);
        void Compare(IShellItem psi, uint hint, out int piOrder);
    }

    [ComImport]
    [Guid("D57C7288-D4AD-4768-BE02-9D969532D960")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IFileOpenDialog
    {
        [PreserveSig]
        int Show(IntPtr parent);
        void SetFileTypes(uint cFileTypes, IntPtr rgFilterSpec);
        void SetFileTypeIndex(uint iFileType);
        void GetFileTypeIndex(out uint piFileType);
        void Advise(IntPtr pfde, out uint pdwCookie);
        void Unadvise(uint dwCookie);
        void SetOptions(FileOpenOptions fos);
        void GetOptions(out FileOpenOptions pfos);
        void SetDefaultFolder(IShellItem psi);
        void SetFolder(IShellItem psi);
        void GetFolder(out IShellItem ppsi);
        void GetCurrentSelection(out IShellItem ppsi);
        void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string pszName);
        void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string pszTitle);
        void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string pszText);
        void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
        void GetResult(out IShellItem ppsi);
        void AddPlace(IShellItem psi, int fdap);
        void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string pszDefaultExtension);
        void Close(int hr);
        void SetClientGuid([MarshalAs(UnmanagedType.LPStruct)] Guid guid);
        void ClearClientData();
        void SetFilter(IntPtr pFilter);
        void GetResults(out IntPtr ppenum);
        void GetSelectedItems(out IntPtr ppsai);
    }

    [Flags]
    private enum FileOpenOptions : uint
    {
        PickFolders = 0x00000020,
        ForceFilesystem = 0x00000040,
        PathMustExist = 0x00000800,
    }

    private enum ShellItemDisplayName : uint
    {
        FileSystemPath = 0x80058000,
    }
}
