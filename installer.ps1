<#
NexShell installer.

WARNING
- This overwrites your PowerShell profile setup. No merge. No restore.
- If anything breaks later, rerun this installer to reinstall everything.
#>

$ErrorActionPreference = 'Stop'

function Write-Header {
    param([Parameter(Mandatory = $true)][string] $Text)
    Write-Host ''
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ('=' * $Text.Length) -ForegroundColor Cyan
}

function Read-YesNo {
    param([Parameter(Mandatory = $true)][string] $Prompt)

    while ($true) {
        $ans = Read-Host $Prompt
        if ($null -eq $ans) { continue }
        $a = $ans.Trim().ToLower()

        if ($a -eq 'y' -or $a -eq 'yes') { return $true }
        if ($a -eq 'n' -or $a -eq 'no') { return $false }

        Write-Host "Please enter 'y' or 'n' (or 'yes'/'no')." -ForegroundColor Yellow
    }
}

function Get-DocumentsPath {
    try {
        $p = [Environment]::GetFolderPath('MyDocuments')
        if ($p) { return $p }
    }
    catch { }

    if ($env:USERPROFILE) { return (Join-Path $env:USERPROFILE 'Documents') }
    return $null
}

function Try-GetGitHubRepoFromOrigin {
    param([Parameter(Mandatory = $true)][string] $SourceRoot)

    try {
        if (-not (Test-Path -Path (Join-Path $SourceRoot '.git'))) { return $null }
        $git = Get-Command -Name 'git' -ErrorAction SilentlyContinue
        if (-not $git) { return $null }

        $url = & $git.Source -C $SourceRoot remote get-url origin 2>$null
        if (-not $url) { return $null }
        $u = ($url | Select-Object -First 1).Trim()
        if (-not $u) { return $null }

        $m = [Regex]::Match($u, 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?$', 'IgnoreCase')
        if ($m.Success) {
            return ("{0}/{1}" -f $m.Groups['owner'].Value, $m.Groups['repo'].Value)
        }
    }
    catch { }

    return $null
}

function Install-NexShellTo {
    param(
        [Parameter(Mandatory = $true)][string] $PackageRoot,
        [Parameter(Mandatory = $true)][string] $TargetDir,
        [Parameter(Mandatory = $true)][bool] $AutoUpdate,
        [string] $Repo
    )

    if (-not (Test-Path -Path $TargetDir)) {
        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    }

    # This is the "NO MATTER WHAT" part: we remove whatever was there for these paths.
    $pathsToRemove = @(
        (Join-Path $TargetDir 'Microsoft.PowerShell_profile.ps1'),
        (Join-Path $TargetDir 'main.ps1'),
        (Join-Path $TargetDir 'config.toml'),
        (Join-Path $TargetDir 'installer.ps1'),
        (Join-Path $TargetDir 'fns'),
        (Join-Path $TargetDir '.nexshell_repo'),
        (Join-Path $TargetDir '.nexshell.sha')
    )

    foreach ($p in $pathsToRemove) {
        try {
            if (Test-Path -Path $p) {
                try {
                    Remove-Item -Path $p -Recurse -Force
                }
                catch {
                    # When reinstalling "in place", the running installer may be locked.
                    # Still continue; we'll overwrite on copy.
                    if ($p -like '*installer.ps1') { continue }
                    throw
                }
            }
        }
        catch {
            throw ("Failed removing '{0}': {1}" -f $p, $_.Exception.Message)
        }
    }

    try {
        Copy-Item -Path (Join-Path $PackageRoot 'Microsoft.PowerShell_profile.ps1') -Destination (Join-Path $TargetDir 'Microsoft.PowerShell_profile.ps1') -Force
        Copy-Item -Path (Join-Path $PackageRoot 'main.ps1') -Destination (Join-Path $TargetDir 'main.ps1') -Force
        Copy-Item -Path (Join-Path $PackageRoot 'installer.ps1') -Destination (Join-Path $TargetDir 'installer.ps1') -Force
        Copy-Item -Path (Join-Path $PackageRoot 'fns') -Destination (Join-Path $TargetDir 'fns') -Recurse -Force
    }
    catch {
        throw ("Copy failed: {0}" -f $_.Exception.Message)
    }

    $cfg = if ($AutoUpdate) { 'true' } else { 'false' }
    try {
        ("auto_update = {0}`r`n" -f $cfg) | Set-Content -Path (Join-Path $TargetDir 'config.toml') -Encoding UTF8 -Force
    }
    catch {
        throw ("Failed writing config.toml: {0}" -f $_.Exception.Message)
    }

    if ($Repo) {
        try {
            ($Repo.Trim() + "`r`n") | Set-Content -Path (Join-Path $TargetDir '.nexshell_repo') -Encoding UTF8 -Force
        }
        catch {
            throw ("Failed writing .nexshell_repo: {0}" -f $_.Exception.Message)
        }
    }
}

try { Clear-Host } catch { }

Write-Header 'NexShell Installer'
Write-Host '1) It will delete any previous data in your profile, NO MATTER WHAT.' -ForegroundColor Red
Write-Host '2) If something breaks completely at some point, try reinstalling everything with this script.' -ForegroundColor Yellow
Write-Host ''
Write-Host 'Press Enter to continue, or Ctrl+C to cancel.' -ForegroundColor Gray
[void](Read-Host)

$autoUpdate = Read-YesNo -Prompt "Would you like to enable auto update? Please note this adds overhead for PowerShell loading as it will have to check for updates before letting you use it. This will not prompt you upon finding an update and find it automatically. Saying no will let you update and check for updates via 'upd' and 'chkupd'. (y/n)"

$sourceRoot = $null
try { $sourceRoot = $PSScriptRoot } catch { $sourceRoot = $null }
if (-not $sourceRoot) {
    try { $sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path } catch { $sourceRoot = $null }
}
if (-not $sourceRoot) { throw 'Unable to determine installer location.' }

foreach ($req in @('Microsoft.PowerShell_profile.ps1', 'main.ps1', 'fns')) {
    if (-not (Test-Path -Path (Join-Path $sourceRoot $req))) {
        throw ("Missing required file/folder next to installer: {0}" -f $req)
    }
}

$repo = $null
if ($autoUpdate) {
    $repo = Try-GetGitHubRepoFromOrigin -SourceRoot $sourceRoot
    if (-not $repo) {
        Write-Host ''
        Write-Host "Auto update needs your GitHub repo in the form 'owner/repo'." -ForegroundColor Yellow
        $repoInput = Read-Host 'Enter GitHub repo (owner/repo). Leave blank to skip'
        if ($repoInput) { $repo = $repoInput.Trim() }
    }
}

$documents = Get-DocumentsPath
if (-not $documents) { throw 'Unable to locate your Documents folder.' }

$targets = @(
    (Join-Path $documents 'PowerShell'),
    (Join-Path $documents 'WindowsPowerShell')
)

Write-Header 'Staging'
$stageRoot = Join-Path ([IO.Path]::GetTempPath()) ('NexShell-Install-' + [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

    Copy-Item -Path (Join-Path $sourceRoot 'Microsoft.PowerShell_profile.ps1') -Destination (Join-Path $stageRoot 'Microsoft.PowerShell_profile.ps1') -Force
    Copy-Item -Path (Join-Path $sourceRoot 'main.ps1') -Destination (Join-Path $stageRoot 'main.ps1') -Force
    Copy-Item -Path (Join-Path $sourceRoot 'installer.ps1') -Destination (Join-Path $stageRoot 'installer.ps1') -Force
    Copy-Item -Path (Join-Path $sourceRoot 'fns') -Destination (Join-Path $stageRoot 'fns') -Recurse -Force
}
catch {
    throw ("Unable to stage install files: {0}" -f $_.Exception.Message)
}

Write-Header 'Installing'
try {
    foreach ($t in $targets) {
        Write-Host ("- {0}" -f $t)
        Install-NexShellTo -PackageRoot $stageRoot -TargetDir $t -AutoUpdate $autoUpdate -Repo $repo
    }
}
finally {
    try {
        if (Test-Path -Path $stageRoot) { Remove-Item -Path $stageRoot -Recurse -Force }
    }
    catch { }
}

Write-Header 'Done'
Write-Host 'Restart PowerShell to pick up the new profile.' -ForegroundColor Green
if ($autoUpdate) {
    if ($repo) {
        Write-Host 'Auto update is enabled.' -ForegroundColor Green
    }
    else {
        Write-Host "Auto update is enabled, but no repo is configured. Set it in '.nexshell_repo' in your profile folder." -ForegroundColor Yellow
    }
}
else {
    Write-Host "Auto update is disabled. Use 'chkupd' and 'upd' when you want." -ForegroundColor Gray
}

