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
    Write-Host ("==> {0}" -f $Text)
}

function Read-YesNo {
    param([Parameter(Mandatory = $true)][string] $Prompt)

    while ($true) {
        $ans = Read-Host $Prompt
        if ($null -eq $ans) { continue }
        $a = $ans.Trim().ToLower()

        if ($a -eq 'y' -or $a -eq 'yes') { return $true }
        if ($a -eq 'n' -or $a -eq 'no') { return $false }

        Write-Host "Please enter 'y' or 'n' (or 'yes'/'no')"
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

function Get-ProfilePathForThisHost {
    # $PROFILE is usually the CurrentUserCurrentHost path, but it can also be a PSObject with properties.
    try {
        if ($PROFILE -is [string]) {
            if ($PROFILE) { return [string] $PROFILE }
        }
        elseif ($PROFILE -and $PROFILE.CurrentUserCurrentHost) {
            return [string] $PROFILE.CurrentUserCurrentHost
        }
    }
    catch { }

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

function Add-ToPathIfMissing {
    param([Parameter(Mandatory = $true)][string] $Dir)

    if (-not $Dir) { return }
    if (-not (Test-Path -Path $Dir)) { return }

    $p = $env:PATH
    if (-not $p) { $env:PATH = $Dir; return }

    foreach ($seg in @($p -split ';')) {
        if ($seg -and ($seg.Trim().TrimEnd('\') -ieq $Dir.Trim().TrimEnd('\'))) {
            return
        }
    }

    $env:PATH = ($Dir + ';' + $p)
}

function Ensure-Tls12 {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
}

function Try-GetOriginUrlFromGitConfig {
    param([Parameter(Mandatory = $true)][string] $TargetDir)

    $cfg = Join-Path $TargetDir '.git\config'
    if (-not (Test-Path -Path $cfg)) { return $null }

    try {
        $lines = Get-Content -Path $cfg -ErrorAction Stop
    }
    catch {
        return $null
    }

    $inOrigin = $false
    foreach ($line in $lines) {
        if ($null -eq $line) { continue }
        $l = [string] $line

        if ($l -match '^\s*\[remote\s+"origin"\]\s*$') { $inOrigin = $true; continue }
        if ($l -match '^\s*\[') { $inOrigin = $false; continue }

        if ($inOrigin -and $l -match '^\s*url\s*=\s*(?<u>.+?)\s*$') {
            $u = $Matches['u']
            if ($u) { return $u.Trim() }
            return $null
        }
    }

    return $null
}

function Test-OriginUrlMatchesRepo {
    param(
        [Parameter(Mandatory = $true)][string] $OriginUrl,
        [Parameter(Mandatory = $true)][string] $Repo
    )

    if (-not $OriginUrl) { return $false }
    if (-not $Repo) { return $false }

    $pattern = "([/:]){0}(?:\.git)?/?$" -f [Regex]::Escape($Repo.Trim())
    return [Regex]::IsMatch($OriginUrl.Trim(), $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function Get-ScoopCommandPath {
    $cmd = Get-Command -Name 'scoop' -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }

    if (-not $env:USERPROFILE) { return $null }
    $shims = Join-Path $env:USERPROFILE 'scoop\shims'
    foreach ($c in @('scoop.cmd', 'scoop.ps1', 'scoop.exe')) {
        $p = Join-Path $shims $c
        if (Test-Path -Path $p) { return $p }
    }

    return $null
}

function Ensure-ScoopInstalled {
    if (Get-ScoopCommandPath) { return }

    Write-Header 'Installing Scoop'
    Ensure-Tls12

    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force | Out-Null
    }
    catch {
        Write-Host "couldn't set ExecutionPolicy for CurrentUser: $($_.Exception.Message)"
    }

    $scriptText = $null
    try {
        if (Get-Command -Name Invoke-RestMethod -ErrorAction SilentlyContinue) {
            $scriptText = Invoke-RestMethod -Uri 'https://get.scoop.sh' -ErrorAction Stop
        }
    }
    catch { $scriptText = $null }

    if (-not $scriptText) {
        try {
            if (Get-Command -Name Invoke-WebRequest -ErrorAction SilentlyContinue) {
                $r = Invoke-WebRequest -Uri 'https://get.scoop.sh' -UseBasicParsing -ErrorAction Stop
                $scriptText = $r.Content
            }
        }
        catch { $scriptText = $null }
    }

    if (-not $scriptText) {
        try {
            $wc = New-Object Net.WebClient
            $scriptText = $wc.DownloadString('https://get.scoop.sh')
        }
        catch { $scriptText = $null }
    }

    if (-not $scriptText) {
        throw "couldn't download scoop installer (no internet / tls / proxy issue)"
    }

    try {
        Invoke-Expression $scriptText
    }
    catch {
        throw ("scoop install failed: {0}" -f $_.Exception.Message)
    }

    if (-not $env:USERPROFILE) { return }
    Add-ToPathIfMissing -Dir (Join-Path $env:USERPROFILE 'scoop\shims')

    if (-not (Get-ScoopCommandPath)) {
        throw "Scoop installation completed, but the 'scoop' command is not available. Please ensure Scoop is properly configured and try again."
    }
}

function Ensure-GitInstalled {
    if (Get-Command -Name 'git' -ErrorAction SilentlyContinue) { return }

    Write-Header 'Git is missing'
    Write-Host "Git is not installed. Please install Git first."
    Write-Host 'Attempting to install Git using Scoop...'

    try {
        Ensure-ScoopInstalled
    }
    catch {
        throw ("Git is not installed and Scoop could not be installed. {0}`nPlease install Git first and rerun this installer." -f $_.Exception.Message)
    }

    $scoop = Get-ScoopCommandPath
    if (-not $scoop) {
        throw "Scoop appears to be installed, but the 'scoop' command is not available. Please ensure Scoop is properly configured and try again."
    }

    try {
        & $scoop install git | Out-Null
        if ($LASTEXITCODE -ne 0) { throw ("Scoop install git failed (exit code {0})" -f $LASTEXITCODE) }
    }
    catch {
        throw ("Failed to install Git via Scoop: {0}`nPlease install Git manually and rerun this installer." -f $_.Exception.Message)
    }

    if ($env:USERPROFILE) {
        Add-ToPathIfMissing -Dir (Join-Path $env:USERPROFILE 'scoop\shims')
    }

    if (-not (Get-Command -Name 'git' -ErrorAction SilentlyContinue)) {
        throw "Git is still not available after installation. Please restart PowerShell and rerun the installer."
    }
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
    if (-not $zipNs) { throw 'unable to open zip file for extraction' }
    $destNs = $shell.NameSpace($Destination)
    if (-not $destNs) { throw 'unable to open destination folder for extraction' }
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
        throw 'this installer requires powershell 3+ (invoke-webrequest)'
    }

    Ensure-Tls12

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('NexShell-Package-' + [Guid]::NewGuid().ToString('N'))
    $zip = Join-Path $tmp 'repo.zip'
    $extract = Join-Path $tmp 'extract'

    New-Item -ItemType Directory -Path $extract -Force | Out-Null

    $zipUrl = "https://github.com/$Repo/archive/refs/heads/main.zip"
    $headers = @{ 'User-Agent' = 'NexShell' }

    Write-Host "downloading package from github..."
    try {
        Invoke-WebRequest -Uri $zipUrl -Headers $headers -OutFile $zip -UseBasicParsing -ErrorAction Stop | Out-Null
    }
    catch {
        Invoke-WebRequest -Uri $zipUrl -Headers $headers -OutFile $zip -ErrorAction Stop | Out-Null
    }

    Write-Host "extracting package..."
    Expand-ZipTo -ZipPath $zip -Destination $extract

    $repoRoot = Get-ChildItem -Path $extract -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $repoRoot) { throw 'downloaded archive did not contain a root folder' }

    foreach ($req in @('Microsoft.PowerShell_profile.ps1', 'main.ps1', 'installer.ps1', 'fns')) {
        if (-not (Test-Path -Path (Join-Path $repoRoot.FullName $req))) {
            throw ("downloaded package missing: {0}" -f $req)
        }
    }

    return @{
        TempRoot   = $tmp
        PackageDir = $repoRoot.FullName
    }
}

function Install-NexShellTo {
    param(
        [string] $PackageRoot,
        [Parameter(Mandatory = $true)][string] $TargetDir,
        [Parameter(Mandatory = $true)][string] $UpdateChannel,
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

    $isGitRepo = Test-Path -Path (Join-Path $TargetDir '.git')
    $git = Get-Command -Name 'git' -ErrorAction SilentlyContinue

    $usedGitInstall = $false
    if ($isGitRepo -and $git) {
        # If the profile folder is a git checkout, prefer a git "full reinstall":
        # it preserves expected line endings and avoids leaving the repo dirty.
        $originStr = ''
        try {
            $origin = & $git.Source -C $TargetDir remote get-url origin 2>$null
            if ($LASTEXITCODE -eq 0 -and $origin) {
                $originStr = (($origin | Select-Object -First 1).Trim())
            }
        }
        catch { $originStr = '' }

        if ($originStr -and (Test-OriginUrlMatchesRepo -OriginUrl $originStr -Repo $Repo)) {
            try { Clear-Host } catch { }
            Write-Host "updating repository via git..."
            & $git.Source -C $TargetDir fetch --prune origin main 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "git fetch failed. check internet/auth and rerun" }

            Write-Host "resetting to latest version..."
            & $git.Source -C $TargetDir reset --hard origin/main 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "git reset failed. check your repo and rerun" }

            $usedGitInstall = $true
            $Sha = $null
            try { $Sha = (& $git.Source -C $TargetDir rev-parse HEAD 2>$null | Select-Object -First 1).Trim() } catch { $Sha = $null }
        }
    }

    if (-not $usedGitInstall) {
        Write-Host "copying files..."
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
                throw ("failed removing '{0}': {1}" -f $p, $_.Exception.Message)
            }
        }

        if (-not $PackageRoot) { throw 'internal error: packageroot is required for non-git install' }

        try {
            Copy-Item -Path (Join-Path $PackageRoot 'Microsoft.PowerShell_profile.ps1') -Destination (Join-Path $TargetDir 'Microsoft.PowerShell_profile.ps1') -Force
            Copy-Item -Path (Join-Path $PackageRoot 'main.ps1') -Destination (Join-Path $TargetDir 'main.ps1') -Force
            Copy-Item -Path (Join-Path $PackageRoot 'installer.ps1') -Destination (Join-Path $TargetDir 'installer.ps1') -Force
            Copy-Item -Path (Join-Path $PackageRoot 'fns') -Destination (Join-Path $TargetDir 'fns') -Recurse -Force
        }
        catch {
            throw ("copy failed: {0}" -f $_.Exception.Message)
        }
    }

    $channel = if ($UpdateChannel) { $UpdateChannel.Trim() } else { 'stable' }
    try {
        ("update_channel = \"{0}\"`r`n" -f $channel) | Set-Content -Path (Join-Path $TargetDir 'config.toml') -Encoding UTF8 -Force
    }
    catch {
        throw ("failed writing config.toml: {0}" -f $_.Exception.Message)
    }

    try {
        ($Repo.Trim() + "`r`n") | Set-Content -Path (Join-Path $TargetDir '.nexshell_repo') -Encoding UTF8 -Force
    }
    catch {
        throw ("failed writing .nexshell_repo: {0}" -f $_.Exception.Message)
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
Write-Host 'welcome to the nexshell installer!'
Write-Host 'please note:'
Write-Host '- this will replace your existing powershell profile. any customizations will be lost.'
Write-Host '- if issues arise, you can reinstall using this script.'
Write-Host 'press enter to continue, or ctrl+c to cancel.'
[void](Read-Host)

try { Clear-Host } catch { }
Write-Header 'Disclaimer'
Write-Host '**you** are solely responsible for choosing to install, and this project is not provided with any warranty as it is sourced under the mit license.'
Write-Host 'press enter to continue, or ctrl+c to cancel.'
[void](Read-Host)

try { Clear-Host } catch { }

function Read-UpdateChannel {
    param(
        [string] $Prompt = 'Choose update channel (stable/beta/nightly) [stable]:'
    )

    while ($true) {
        $ans = Read-Host $Prompt
        if ($null -eq $ans -or $ans.Trim() -eq '') { return 'stable' }

        $val = $ans.Trim().ToLower()
        if ($val -in @('stable', 'beta', 'nightly')) { return $val }

        Write-Host "Please enter 'stable', 'beta', or 'nightly'."
    }
}

$updateChannel = Read-UpdateChannel

$repo = 'nexoude/nexshell'

$profilePath = Get-ProfilePathForThisHost
if (-not $profilePath) { throw 'Unable to determine $PROFILE for this host.' }

$target = Split-Path -Parent $profilePath
if (-not $target) { throw 'Unable to determine profile directory from $PROFILE.' }

try { Clear-Host } catch { }
Write-Header 'Preparing'
$needGit = $false
$needPackage = $true

$gitDir = Join-Path $target '.git'
if (Test-Path -Path $gitDir) {
    $originUrl = Try-GetOriginUrlFromGitConfig -TargetDir $target
    if ($originUrl -and (Test-OriginUrlMatchesRepo -OriginUrl $originUrl -Repo $repo)) {
        $needGit = $true
        $needPackage = $false
    }
}

if ($needGit) {
    try {
        Ensure-GitInstalled
    }
    catch {
        Write-Error -Message $_.Exception.Message -ErrorAction Continue
        throw
    }
}

$pkg = $null
if ($needPackage) {
    try { Clear-Host } catch { }
Write-Header 'Downloading'
    try {
        $pkg = Download-NexShellPackage -Repo $repo
    }
    catch {
        Write-Error -Message $_.Exception.Message -ErrorAction Continue
        Write-Host 'hint: this needs internet access to github (and may require tls 1.2 / proxy settings on older systems)'
        throw
    }
}

$sha = $null
try { $sha = Get-LatestSha -Repo $repo } catch { $sha = $null }

try { Clear-Host } catch { }
Write-Header 'Installing'
try {
    Write-Host ("target: {0}" -f $target)
    $pkgRoot = if ($pkg) { $pkg.PackageDir } else { $null }
    Install-NexShellTo -PackageRoot $pkgRoot -TargetDir $target -UpdateChannel $updateChannel -Repo $repo -Sha $sha
}
finally {
    try {
        if ($pkg -and $pkg.TempRoot -and (Test-Path -Path $pkg.TempRoot)) {
            Write-Host "cleaning up temporary files..."
            Remove-Item -Path $pkg.TempRoot -Recurse -Force
        }
    }
    catch { }
}

try { Clear-Host } catch { }
Write-Header 'Done'
Write-Host 'nexshell has been installed successfully!'
Write-Host 'please restart powershell to apply the new profile.'
if ($autoUpdate) {
    Write-Host 'auto-update is enabled.'
}
else {
    Write-Host "auto-update is disabled. use 'chkupd' and 'upd' to check for and install updates manually."
}

