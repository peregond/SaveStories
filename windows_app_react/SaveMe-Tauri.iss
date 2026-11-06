; Установщик SaveMe (React + Tauri). AppId и папка установки совпадают с установщиком WinUI-клиента,
; поэтому новая версия ставится поверх старой, а встроенное обновление находит unins000.exe.
#define MyAppName "SaveMe Windows"
#define MyAppExeName "SaveMe-Windows.exe"
#define MyAppVersion GetEnv("SAVESTORIES_VERSION")

[Setup]
AppId={{D9F59F3E-A19A-4E8D-9F2B-9841F1A35D55}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher=SaveMe
DefaultDirName={localappdata}\Programs\SaveMeWindows
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupIconFile={#SourcePath}src-tauri\icons\icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
ChangesAssociations=no
PrivilegesRequired=lowest
CloseApplications=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion; Excludes: "MicrosoftEdgeWebview2Setup.exe"
; Загрузчик WebView2 нужен только на Windows 10 без Edge WebView2 Runtime; на Windows 11 он уже есть.
Source: "{#SourceDir}\MicrosoftEdgeWebview2Setup.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: not WebView2Installed

[InstallDelete]
Type: filesandordirs; Name: "{app}\*"

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{tmp}\MicrosoftEdgeWebview2Setup.exe"; Parameters: "/silent /install"; StatusMsg: "Устанавливаю Microsoft Edge WebView2…"; Flags: waituntilterminated; Check: not WebView2Installed
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
; Обновление изнутри приложения идёт в тихом режиме с /RELAUNCH: запускаем новую версию сами.
Filename: "{app}\{#MyAppExeName}"; Flags: nowait; Check: RelaunchRequested

[UninstallRun]
Filename: "{cmd}"; Parameters: "/C taskkill /IM ""SaveMe-Windows.exe"" /F /T >NUL 2>NUL & exit /B 0"; Flags: runhidden waituntilterminated; RunOnceId: "KillSaveMe"
Filename: "{cmd}"; Parameters: "/C taskkill /IM ""SaveMe.WinUI.exe"" /F /T >NUL 2>NUL & exit /B 0"; Flags: runhidden waituntilterminated; RunOnceId: "KillSaveStoriesWindows"
Filename: "{cmd}"; Parameters: "/C taskkill /IM ""SaveStories.WinUI.Beta.exe"" /F /T >NUL 2>NUL & exit /B 0"; Flags: runhidden waituntilterminated; RunOnceId: "KillWinUI"
Filename: "{cmd}"; Parameters: "/C taskkill /IM ""SaveStories-Windows.exe"" /F /T >NUL 2>NUL & exit /B 0"; Flags: runhidden waituntilterminated; RunOnceId: "KillWinUIBeta"

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
Type: filesandordirs; Name: "{localappdata}\Programs\SaveMeWindows"
Type: filesandordirs; Name: "{localappdata}\Programs\SaveStoriesWinUIBeta"
Type: filesandordirs; Name: "{localappdata}\SaveMe"
Type: filesandordirs; Name: "{localappdata}\SaveMe.WinUI"
Type: filesandordirs; Name: "{localappdata}\SaveMe.WinUI.Beta"
Type: filesandordirs; Name: "{localappdata}\SaveStories"
Type: filesandordirs; Name: "{localappdata}\SaveStories.WinUI"
Type: filesandordirs; Name: "{localappdata}\SaveStories.WinUI.Beta"
Type: filesandordirs; Name: "{localappdata}\DimaSave"
Type: filesandordirs; Name: "{userappdata}\SaveMe"
Type: filesandordirs; Name: "{userappdata}\SaveMe.WinUI"
Type: filesandordirs; Name: "{userappdata}\SaveMe.WinUI.Beta"
Type: filesandordirs; Name: "{userappdata}\SaveStories"
Type: filesandordirs; Name: "{userappdata}\SaveStories.WinUI"
Type: filesandordirs; Name: "{userappdata}\SaveStories.WinUI.Beta"
Type: filesandordirs; Name: "{userappdata}\DimaSave"

[Registry]
Root: HKCU; Subkey: "Software\SaveMe"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\SaveMe.WinUI"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\SaveMe.WinUI.Beta"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\SaveStories"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\SaveStories.WinUI"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\SaveStories.WinUI.Beta"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\DimaSave"; Flags: uninsdeletekey

[Code]
function RelaunchRequested: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), '/RELAUNCH') = 0 then
      Result := True;
end;

const
  WebView2ClientKey = 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}';

function HasWebView2Version(RootKey: Integer; const SubKey: String): Boolean;
var
  Version: String;
begin
  Result := False;
  if RegQueryStringValue(RootKey, SubKey, 'pv', Version) then
    Result := (Version <> '') and (Version <> '0.0.0.0');
end;

function WebView2Installed: Boolean;
begin
  Result := HasWebView2Version(HKLM32, WebView2ClientKey) or HasWebView2Version(HKCU, WebView2ClientKey);
end;
