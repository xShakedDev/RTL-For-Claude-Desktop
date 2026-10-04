$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
function Log($m) { Write-Host ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $m) }
$url = 'https://downloads.claude.ai/releases/win32/x64/1.44121.2/Claude-817a7b4563855a33d4b678faefc71f87554445d8.msix'
Log 'downloading'
curl.exe -sSL --max-time 600 -o claude.msix $url
Log ('downloaded bytes: ' + (Get-Item claude.msix).Length)
Log ("SHA256: " + (Get-FileHash claude.msix).Hash)
Log 'installing'
Add-AppxPackage .\claude.msix
Log 'installed'
$p = Get-AppxPackage -Name Claude
$p | Format-List Name, PackageFamilyName, Version, InstallLocation
$m = Get-AppxPackageManifest $p
"--- Applications"
foreach ($a in @($m.Package.Applications.Application)) { "Id=$($a.Id) Executable=$($a.Executable)" }
"--- Alias present: " + ($m.OuterXml -match 'AppExecutionAlias')
$app = @($m.Package.Applications.Application)[0]
$exe = Join-Path $p.InstallLocation $app.Executable

Add-Type @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class W {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  static string D(IntPtr h, string kind) {
    var c = new StringBuilder(256); GetClassName(h, c, 256);
    var t = new StringBuilder(256); GetWindowText(h, t, 256);
    int ex = GetWindowLong(h, -20);
    return kind + " visible=" + IsWindowVisible(h) + " RTL_LAYOUT=" + ((ex & 0x400000) != 0) + " class=" + c + " title=" + t;
  }
  public static List<string> Scan(uint[] pids) {
    var set = new HashSet<uint>(pids); var r = new List<string>();
    EnumWindows((h, l) => {
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (set.Contains(pid)) {
        r.Add(D(h, "top"));
        EnumChildWindows(h, (c, l2) => { r.Add("  " + D(c, "child")); return true; }, IntPtr.Zero);
      }
      return true;
    }, IntPtr.Zero);
    return r;
  }
}
"@

function Stop-Claude { Get-Process -Name claude -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 5 }
function Report($label) {
  Start-Sleep 35
  Log "=================== $label"
  $procs = @(Get-CimInstance Win32_Process -Filter "Name='claude.exe'")
  "processes: $($procs.Count)"
  $procs | Where-Object { $_.CommandLine -notmatch '--type=' } | ForEach-Object { "main cmdline: $($_.CommandLine)" }
  "flag reached a process: " + [bool]($procs | Where-Object { $_.CommandLine -match 'force-ui-direction=ltr' })
  if ($procs.Count) { [W]::Scan([uint32[]]($procs | ForEach-Object { [uint32]$_.ProcessId })) | Where-Object { $_ -match 'visible=True' } | Select-Object -First 25 }
  Stop-Claude
}

Stop-Claude
Log 'launch A'
Invoke-CommandInDesktopPackage -PackageFamilyName $p.PackageFamilyName -AppId $app.Id -Command $exe -Args '--lang=he'
Report 'A. Hebrew UI, no fix (Invoke-CommandInDesktopPackage)'

Invoke-CommandInDesktopPackage -PackageFamilyName $p.PackageFamilyName -AppId $app.Id -Command $exe -Args '--lang=he --force-ui-direction=ltr'
Report 'B. Hebrew UI + --force-ui-direction=ltr (Invoke-CommandInDesktopPackage)'

Start-Process -FilePath $exe -ArgumentList '--lang=he'
Report 'C. Hebrew UI, no fix (direct exe)'

Start-Process -FilePath $exe -ArgumentList '--lang=he','--force-ui-direction=ltr'
Report 'D. Hebrew UI + --force-ui-direction=ltr (direct exe)'
