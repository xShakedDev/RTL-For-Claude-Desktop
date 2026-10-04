$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
function Log($m) { Write-Host ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $m) }
$fails = 0
function Check($name, $ok) { if ($ok) { Log "PASS  $name" } else { Log "FAIL  $name"; $script:fails++ } }

$url = 'https://downloads.claude.ai/releases/win32/x64/1.44121.2/Claude-817a7b4563855a33d4b678faefc71f87554445d8.msix'
curl.exe -sSL --max-time 600 -o claude.msix $url
Add-AppxPackage .\claude.msix
$p = Get-AppxPackage -Name Claude
Log "installed $($p.Version)"

function Main { @(Get-CimInstance Win32_Process -Filter "Name='claude.exe'" | Where-Object { $_.CommandLine -notmatch '--type=' }) }
function HasFlag { [bool](Main | Where-Object { $_.CommandLine -like '*--force-ui-direction=ltr*' }) }
function All { @(Get-CimInstance Win32_Process -Filter "Name='claude.exe'") }
function Show($tag) { foreach ($m in Main) { Log "  $tag main pid=$($m.ProcessId) cmd=$($m.CommandLine)" }; Log "  $tag total claude.exe: $(@(All).Count)" }
function Stop-All {
  foreach ($x in All) { try { Stop-Process -Id $x.ProcessId -Force -ErrorAction Stop } catch { Log "  stop $($x.ProcessId) failed: $($_.Exception.Message)" } }
  for ($i = 0; $i -lt 20 -and @(All).Count; $i++) { Start-Sleep -Milliseconds 500 }
  Log "  after stop: $(@(All).Count) claude.exe left"
}

# 1. Install shortcuts
& powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\claude-ltr.ps1 -Install
$desk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Claude (LTR).lnk'
$menu = Join-Path ([Environment]::GetFolderPath('Programs')) 'Claude (LTR).lnk'
Check 'desktop shortcut created' (Test-Path $desk)
Check 'start menu shortcut created' (Test-Path $menu)
Check 'icon extracted' ((Get-Item "$env:LOCALAPPDATA\ClaudeLTR\claude.ico" -ErrorAction SilentlyContinue).Length -gt 0)
$lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($desk)
Log "shortcut: $($lnk.TargetPath) $($lnk.Arguments)"

function Click { $pr = Start-Process -FilePath $lnk.TargetPath -ArgumentList $lnk.Arguments -PassThru; $done = $pr.WaitForExit(90000); Log "launcher exited: $done" }

# 2. Launch through the shortcut's exact command (Claude not running)
Click
Start-Sleep 30
Show 'now'
Check 'cold start: Claude running with the flag' (HasFlag)

# 3. Claude started normally (no flag), then the shortcut restarts it with the flag
Stop-All
$app = @((Get-AppxPackageManifest $p).Package.Applications.Application)[0]
Invoke-CommandInDesktopPackage -PackageFamilyName $p.PackageFamilyName -AppId $app.Id -Command (Join-Path $p.InstallLocation $app.Executable)
Start-Sleep 30
Show 'normal'
Check 'normal start: running without the flag' ((@(Main).Count -gt 0) -and -not (HasFlag))
Click
Start-Sleep 30
Show 'now'
Check 'restart: running with the flag' (HasFlag)
Check 'restart: a single main process' (@(Main).Count -eq 1)

# 4. Shortcut again while already fixed: no restart
$before = @(Main | Where-Object { $_.CommandLine -like '*--force-ui-direction=ltr*' } | ForEach-Object ProcessId)
Click
Start-Sleep 15
Show 'again'
$after = @(Main | Where-Object { $_.CommandLine -like '*--force-ui-direction=ltr*' } | ForEach-Object ProcessId)
Check 'already fixed: not restarted' ($before.Count -ge 1 -and ($after -contains $before[0]))

# 5. Uninstall
Stop-All
& powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\ClaudeLTR\claude-ltr.ps1" -Uninstall
Check 'shortcuts removed' (-not (Test-Path $desk) -and -not (Test-Path $menu))
Check 'install folder removed' (-not (Test-Path "$env:LOCALAPPDATA\ClaudeLTR"))

Log "failures: $fails"
exit $fails
