using Microsoft.UI.Xaml;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace SaveMe.WinUI.Beta.Services;

public static class ShellFolderService
{
    public static async Task<string?> PickFolderAsync(Window? owner, string title, string? initialDirectory = null)
    {
        var picker = new FolderPicker
        {
            SuggestedStartLocation = PickerLocationId.Downloads,
            CommitButtonText = "Выбрать папку",
        };
        picker.FileTypeFilter.Add("*");

        if (owner is not null)
        {
            InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(owner));
        }

        var folder = await picker.PickSingleFolderAsync();
        return folder?.Path;
    }

    public static string? PickFolder(Window? owner, string title, string? initialDirectory = null)
    {
        var dialog = (IFileOpenDialog)new FileOpenDialog();

        try
        {
            dialog.GetOptions(out var options);
            dialog.SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST | FOS_NOCHANGEDIR);
            dialog.SetTitle(title);
            dialog.SetOkButtonLabel("Выбрать папку");

            var initialPath = ExistingDirectoryOrDefault(initialDirectory);
            if (TryCreateShellItem(initialPath, out var initialFolder))
            {
                dialog.SetFolder(initialFolder);
                Marshal.ReleaseComObject(initialFolder);
            }

            var hwnd = owner is null ? IntPtr.Zero : WindowNative.GetWindowHandle(owner);
            var hr = dialog.Show(hwnd);
            if (hr == HRESULT_CANCELLED)
            {
                return null;
            }

            Marshal.ThrowExceptionForHR(hr);
            dialog.GetResult(out var item);
            try
            {
                item.GetDisplayName(SIGDN_FILESYSPATH, out var pathPtr);
                try
                {
                    return Marshal.PtrToStringUni(pathPtr);
                }
                finally
                {
                    Marshal.FreeCoTaskMem(pathPtr);
                }
            }
            finally
            {
                Marshal.ReleaseComObject(item);
            }
        }
        finally
        {
            Marshal.ReleaseComObject(dialog);
        }
    }

    private static bool TryCreateShellItem(string path, out IShellItem item)
    {
        var shellItemId = typeof(IShellItem).GUID;
        var hr = SHCreateItemFromParsingName(path, IntPtr.Zero, ref shellItemId, out item);
        return hr == 0 && item is not null;
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

    private const int HRESULT_CANCELLED = unchecked((int)0x800704C7);
    private const uint SIGDN_FILESYSPATH = 0x80058000;
    private const uint FOS_PICKFOLDERS = 0x00000020;
    private const uint FOS_FORCEFILESYSTEM = 0x00000040;
    private const uint FOS_PATHMUSTEXIST = 0x00000800;
    private const uint FOS_NOCHANGEDIR = 0x00000008;

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
    private static extern int SHCreateItemFromParsingName(
        string pszPath,
        IntPtr pbc,
        ref Guid riid,
        [MarshalAs(UnmanagedType.Interface)] out IShellItem ppv);

    [ComImport]
    [Guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7")]
    private sealed class FileOpenDialog : IFileOpenDialog
    {
        [PreserveSig]
        public extern int Show(IntPtr parent);
        public extern void SetFileTypes(uint cFileTypes, IntPtr rgFilterSpec);
        public extern void SetFileTypeIndex(uint iFileType);
        public extern void GetFileTypeIndex(out uint piFileType);
        public extern void Advise(IntPtr pfde, out uint pdwCookie);
        public extern void Unadvise(uint dwCookie);
        public extern void SetOptions(uint fos);
        public extern void GetOptions(out uint pfos);
        public extern void SetDefaultFolder(IShellItem psi);
        public extern void SetFolder(IShellItem psi);
        public extern void GetFolder(out IShellItem ppsi);
        public extern void GetCurrentSelection(out IShellItem ppsi);
        public extern void SetFileName(string pszName);
        public extern void GetFileName(out string pszName);
        public extern void SetTitle(string pszTitle);
        public extern void SetOkButtonLabel(string pszText);
        public extern void SetFileNameLabel(string pszLabel);
        public extern void GetResult(out IShellItem ppsi);
        public extern void AddPlace(IShellItem psi, uint fdap);
        public extern void SetDefaultExtension(string pszDefaultExtension);
        public extern void Close(int hr);
        public extern void SetClientGuid(ref Guid guid);
        public extern void ClearClientData();
        public extern void SetFilter(IntPtr pFilter);
        public extern void GetResults(out IntPtr ppenum);
        public extern void GetSelectedItems(out IntPtr ppsai);
    }

    [ComImport]
    [Guid("42F85136-DB7E-439C-85F1-E4075D135FC8")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IFileDialog
    {
        [PreserveSig]
        int Show(IntPtr parent);
        void SetFileTypes(uint cFileTypes, IntPtr rgFilterSpec);
        void SetFileTypeIndex(uint iFileType);
        void GetFileTypeIndex(out uint piFileType);
        void Advise(IntPtr pfde, out uint pdwCookie);
        void Unadvise(uint dwCookie);
        void SetOptions(uint fos);
        void GetOptions(out uint pfos);
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
        void AddPlace(IShellItem psi, uint fdap);
        void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string pszDefaultExtension);
        void Close(int hr);
        void SetClientGuid(ref Guid guid);
        void ClearClientData();
        void SetFilter(IntPtr pFilter);
    }

    [ComImport]
    [Guid("D57C7288-D4AD-4768-BE02-9D969532D960")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IFileOpenDialog : IFileDialog
    {
        void GetResults(out IntPtr ppenum);
        void GetSelectedItems(out IntPtr ppsai);
    }

    [ComImport]
    [Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItem
    {
        void BindToHandler(IntPtr pbc, ref Guid bhid, ref Guid riid, out IntPtr ppv);
        void GetParent(out IShellItem ppsi);
        void GetDisplayName(uint sigdnName, out IntPtr ppszName);
        void GetAttributes(uint sfgaoMask, out uint psfgaoAttribs);
        void Compare(IShellItem psi, uint hint, out int piOrder);
    }
}
