#define MyAppName "SaveMe"
#define MyAppExeName "SaveMe-Windows.exe"
#define MyAppVersion GetStringFileInfo(AddBackslash(SourceDir) + MyAppExeName, "ProductVersion")

[Setup]
AppId={{B1A00A8A-E768-4AAB-BBF8-8D431AA2FF64}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppName}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
ChangesAssociations=no
PrivilegesRequired=admin
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[InstallDelete]
Type: filesandordirs; Name: "{app}\*"

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{cmd}"; Parameters: "/C taskkill /IM ""SaveMe-Windows.exe"" /F /T >NUL 2>NUL & exit /B 0"; Flags: runhidden waituntilterminated
Filename: "{cmd}"; Parameters: "/C taskkill /IM ""SaveStories-Windows.exe"" /F /T >NUL 2>NUL & exit /B 0"; Flags: runhidden waituntilterminated
Filename: "{cmd}"; Parameters: "/C taskkill /IM ""SaveMe.WinUI.exe"" /F /T >NUL 2>NUL & exit /B 0"; Flags: runhidden waituntilterminated
Filename: "{cmd}"; Parameters: "/C taskkill /IM ""SaveStories.WinUI.Beta.exe"" /F /T >NUL 2>NUL & exit /B 0"; Flags: runhidden waituntilterminated

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
