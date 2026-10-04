<#
.SYNOPSIS
    Starts Claude Desktop with a left-to-right window layout.

.DESCRIPTION
    On Windows with a Hebrew or Arabic display language, Claude Desktop lays
    out its window right to left: the window controls cover the app's own
    buttons and the browser pane opens in the wrong place. Starting the app
    with Chromium's --force-ui-direction=ltr switch fixes this without
    modifying any of its files.

    claude-ltr.ps1              Start Claude with the fix. If Claude is
                                already running without it, it is restarted.
    claude-ltr.ps1 -Install     Add "Claude (LTR)" shortcuts to the desktop
                                and the Start menu.
    claude-ltr.ps1 -Uninstall   Remove those shortcuts.

.LINK
    https://github.com/xShakedDev/RTL-For-Claude-Desktop
#>
[CmdletBinding(DefaultParameterSetName = 'Start')]
param(
    [Parameter(ParameterSetName = 'Install')][switch]$Install,
    [Parameter(ParameterSetName = 'Uninstall')][switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$Flag = '--force-ui-direction=ltr'
$ShortcutName = 'Claude (LTR)'
$InstallDir = Join-Path $env:LOCALAPPDATA 'ClaudeLTR'
$Shortcuts = @(
    (Join-Path ([Environment]::GetFolderPath('Desktop')) "$ShortcutName.lnk"),
    (Join-Path ([Environment]::GetFolderPath('Programs')) "$ShortcutName.lnk")
)

function Get-Claude {
    $package = Get-AppxPackage -Name 'Claude' |
        Sort-Object Version -Descending | Select-Object -First 1
    if (-not $package) {
        throw 'Claude Desktop is not installed (no "Claude" app package was found).'
    }
    $app = @((Get-AppxPackageManifest $package).Package.Applications.Application)[0]

    [pscustomobject]@{
        Package = $package
        AppId   = $app.Id
        Exe     = Join-Path $package.InstallLocation $app.Executable
    }
}

# Every claude.exe process started from this package (main and helpers).
function Get-ClaudeProcesses($claude) {
    @(Get-CimInstance Win32_Process -Filter "Name = 'claude.exe'" |
        Where-Object { $_.CommandLine -like "*$($claude.Package.InstallLocation)*" })
}

function Start-Claude {
    $claude = Get-Claude
    $processes = Get-ClaudeProcesses $claude
    $main = @($processes | Where-Object { $_.CommandLine -notmatch '--type=' })

    # The switch only takes effect when the app starts, so a running instance
    # without it has to be closed first.
    if ($main.Count -and -not ($main | Where-Object { $_.CommandLine -like "*$Flag*" })) {
        $processes | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        for ($i = 0; $i -lt 20 -and @(Get-ClaudeProcesses $claude).Count; $i++) {
            Start-Sleep -Milliseconds 500
        }
    }

    # Start it inside its app package, as the Start menu would; fall back to
    # running the executable directly.
    try {
        Invoke-CommandInDesktopPackage -PackageFamilyName $claude.Package.PackageFamilyName `
            -AppId $claude.AppId -Command $claude.Exe -Args $Flag
    }
    catch {
        Start-Process -FilePath $claude.Exe -ArgumentList $Flag
    }
}

function Install-Shortcuts {
    $claude = Get-Claude
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

    $script = Join-Path $InstallDir 'claude-ltr.ps1'
    if ($PSCommandPath -ne $script) {
        Copy-Item -LiteralPath $PSCommandPath -Destination $script -Force
    }

    # Keep a copy of Claude's icon: the app's folder changes on every update.
    Add-Type -AssemblyName System.Drawing
    $icon = Join-Path $InstallDir 'claude.ico'
    $stream = [IO.File]::Create($icon)
    try { [Drawing.Icon]::ExtractAssociatedIcon($claude.Exe).Save($stream) }
    finally { $stream.Close() }

    $shell = New-Object -ComObject WScript.Shell
    foreach ($path in $Shortcuts) {
        $shortcut = $shell.CreateShortcut($path)
        $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""
        $shortcut.IconLocation = $icon
        $shortcut.Description = 'Claude with a left-to-right window layout'
        $shortcut.Save()
    }

    Write-Host "Added '$ShortcutName' to the desktop and the Start menu."
}

function Uninstall-Shortcuts {
    foreach ($path in $Shortcuts) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "Removed the '$ShortcutName' shortcuts."
}

switch ($PSCmdlet.ParameterSetName) {
    'Install'   { Install-Shortcuts }
    'Uninstall' { Uninstall-Shortcuts }
    default     { Start-Claude }
}
