<#
NexShell installer (GitHub-based).

WARNING
- This will overwrite your PowerShell profile setup. No merge. No restore.
- It will delete previous NexShell files from your profile folders, NO MATTER WHAT.
- If something breaks later, rerun this installer (it acts like a full reinstall/update).
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

function Expand-ZipTo {
    param(
        [Parameter(Mandatory = $true)][string] $ZipPath,
        [Parameter(Mandatory = $true)][string] $Destination
    )

    if (-not (Test-Path -Path $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    if (Get-Command -Name Expand-Archive -ErrorAction SilentlyContinue) {
        Expand-Archive -Path $ZipPath -DestinationPath $Destination -Force
        return
    }

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop | Out-Null
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $Destination)
        return
    }
    catch { }

    # Old Windows fallback.
    $shell = New-Object -ComObject Shell.Application
    $zipNs = $shell.NameSpace($ZipPath)
    if (-not $zipNs) { throw 'Unable to open zip file for extraction.' }
    $destNs = $shell.NameSpace($Destination)
    if (-not $destNs) { throw 'Unable to open destination folder for extraction.' }
    $destNs.CopyHere($zipNs.Items(), 0x10)
}

function Get-LatestSha {
    param([Parameter(Mandatory = $true)][string] $Repo)

    if (-not (Get-Command -Name Invoke-RestMethod -ErrorAction SilentlyContinue) -and -not (Get-Command -Name Invoke-WebRequest -ErrorAction SilentlyContinue)) {
        return $null
    }

    $uri = "https://api.github.com/repos/$Repo/commits/main"
    $headers = @{ 'User-Agent' = 'NexShell' }

    try {
        if (Get-Command -Name Invoke-RestMethod -ErrorAction SilentlyContinue) {
            $resp = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
            if ($resp -and $resp.sha) { return [string] $resp.sha }
        }
    }
    catch { }

    try {
        $raw = Invoke-WebRequest -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
        if (-not $raw -or -not $raw.Content) { return $null }
        if (-not (Get-Command -Name ConvertFrom-Json -ErrorAction SilentlyContinue)) { return $null }
        $obj = $raw.Content | ConvertFrom-Json
        if ($obj -and $obj.sha) { return [string] $obj.sha }
    }
    catch { }

    return $null
}

function Download-NexShellPackage {
    param([Parameter(Mandatory = $true)][string] $Repo)

    if (-not (Get-Command -Name Invoke-WebRequest -ErrorAction SilentlyContinue)) {
        throw 'This installer requires PowerShell 3+ (Invoke-WebRequest).'
    }

    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('NexShell-Package-' + [Guid]::NewGuid().ToString('N'))
    $zip = Join-Path $tmp 'repo.zip'
    $extract = Join-Path $tmp 'extract'

    New-Item -ItemType Directory -Path $extract -Force | Out-Null

    $zipUrl = "https://github.com/$Repo/archive/refs/heads/main.zip"
    $headers = @{ 'User-Agent' = 'NexShell' }

    try {
        Invoke-WebRequest -Uri $zipUrl -Headers $headers -OutFile $zip -UseBasicParsing -ErrorAction Stop | Out-Null
    }
    catch {
        Invoke-WebRequest -Uri $zipUrl -Headers $headers -OutFile $zip -ErrorAction Stop | Out-Null
    }

    Expand-ZipTo -ZipPath $zip -Destination $extract

    $repoRoot = Get-ChildItem -Path $extract -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $repoRoot) { throw 'Downloaded archive did not contain a root folder.' }

    foreach ($req in @('Microsoft.PowerShell_profile.ps1', 'main.ps1', 'installer.ps1', 'fns')) {
        if (-not (Test-Path -Path (Join-Path $repoRoot.FullName $req))) {
            throw ("Downloaded package missing: {0}" -f $req)
        }
    }

    return @{
        TempRoot   = $tmp
        PackageDir = $repoRoot.FullName
    }
}

function Install-NexShellTo {
    param(
        [Parameter(Mandatory = $true)][string] $PackageRoot,
        [Parameter(Mandatory = $true)][string] $TargetDir,
        [Parameter(Mandatory = $true)][bool] $AutoUpdate,
        [Parameter(Mandatory = $true)][string] $Repo,
        [string] $Sha
    )

    if (-not (Test-Path -Path $TargetDir)) {
        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    }

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

    try {
        ($Repo.Trim() + "`r`n") | Set-Content -Path (Join-Path $TargetDir '.nexshell_repo') -Encoding UTF8 -Force
    }
    catch {
        throw ("Failed writing .nexshell_repo: {0}" -f $_.Exception.Message)
    }

    if ($Sha) {
        try {
            ($Sha.Trim() + "`r`n") | Set-Content -Path (Join-Path $TargetDir '.nexshell.sha') -Encoding UTF8 -Force
        }
        catch { }
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

$repo = $env:NEXSHELL_REPO
if ($repo) { $repo = $repo.Trim() }

if (-not $repo) {
    $here = $null
    try { $here = $PSScriptRoot } catch { $here = $null }
    if ($here) {
        $fromOrigin = Try-GetGitHubRepoFromOrigin -SourceRoot $here
        if ($fromOrigin) { $repo = $fromOrigin }
    }
}

if (-not $repo) { $repo = 'nexoude/nexshell' }

$repoOverride = Read-Host ("GitHub repo to install from [{0}]" -f $repo)
if ($repoOverride) { $repo = $repoOverride.Trim() }
if (-not $repo) { throw 'Repo cannot be empty.' }

Write-Header 'Downloading'
$pkg = $null
try {
    $pkg = Download-NexShellPackage -Repo $repo
}
catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    Write-Host 'Hint: this needs internet access to GitHub (and may require TLS 1.2 / proxy settings on older systems).' -ForegroundColor Yellow
    throw
}

$sha = $null
try { $sha = Get-LatestSha -Repo $repo } catch { $sha = $null }

$documents = Get-DocumentsPath
if (-not $documents) { throw 'Unable to locate your Documents folder.' }

$targets = @(
    (Join-Path $documents 'PowerShell'),
    (Join-Path $documents 'WindowsPowerShell')
)

Write-Header 'Installing'
try {
    foreach ($t in $targets) {
        Write-Host ("- {0}" -f $t)
        Install-NexShellTo -PackageRoot $pkg.PackageDir -TargetDir $t -AutoUpdate $autoUpdate -Repo $repo -Sha $sha
    }
}
finally {
    try {
        if ($pkg -and $pkg.TempRoot -and (Test-Path -Path $pkg.TempRoot)) {
            Remove-Item -Path $pkg.TempRoot -Recurse -Force
        }
    }
    catch { }
}

Write-Header 'Done'
Write-Host 'Restart PowerShell to pick up the new profile.' -ForegroundColor Green
if ($autoUpdate) {
    Write-Host 'Auto update is enabled.' -ForegroundColor Green
}
else {
    Write-Host "Auto update is disabled. Use 'chkupd' and 'upd' when you want." -ForegroundColor Gray
}

