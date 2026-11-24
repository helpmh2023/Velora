; Velora Windows installer (Inno Setup 6).
; Built by scripts/package_windows.ps1, which passes the version and the folder
; with the finished release files:
;   ISCC.exe /DAppVersion=1.0.0 /DSourceDir=dist\Velora-1.0.0-windows-x64 installer\velora.iss

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\dist\Velora-1.0.0-windows-x64"
#endif

[Setup]
AppId={{B7C2D0A4-6E1F-4C58-9D3A-7E4F8A21C5B9}
AppName=Velora
AppVersion={#AppVersion}
AppVerName=Velora {#AppVersion}
AppPublisher=Velora
; Per-user install by default: no admin prompt, lives in %LOCALAPPDATA%\Programs.
; The dialog still lets someone pick "install for all users".
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={autopf}\Velora
DefaultGroupName=Velora
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=Velora-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\velora.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Close a running Velora (and its engine) instead of failing on locked files.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Registry]
; Same setting as Windows Settings > Display > Graphics > Velora > High performance
Root: HKCU; Subkey: "Software\Microsoft\DirectX\UserGpuPreferences"; ValueType: string; ValueName: "{app}\velora.exe"; ValueData: "GpuPreference=2;"; Flags: uninsdeletevalue

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Velora"; Filename: "{app}\velora.exe"
Name: "{autodesktop}\Velora"; Filename: "{app}\velora.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\velora.exe"; Description: "Launch Velora"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Make sure the app and its torrent engine are not holding files open.
Filename: "{cmd}"; Parameters: "/C taskkill /IM velora_engine.exe /F"; Flags: runhidden; RunOnceId: "KillEngine"
Filename: "{cmd}"; Parameters: "/C taskkill /IM velora.exe /F"; Flags: runhidden; RunOnceId: "KillApp"

; Your library, settings and watch progress live in %APPDATA% and are kept on
; uninstall on purpose, so reinstalling picks up where you left off.
