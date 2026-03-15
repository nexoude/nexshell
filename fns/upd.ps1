<#
Do not edit unless you understand what it does.
`upd` installs the latest version (no confirmations).
#>

function upd {
    [CmdletBinding()]
    param(
        [switch] $Force,
        [string] $Channel
    )

    $ErrorActionPreference = 'Stop'

    function Get-InstallRoot {
        $dir = $null
        try { $dir = $PSScriptRoot } catch { $dir = $null }
        if (-not $dir) {
            try { $dir = Split-Path -Parent $MyInvocation.MyCommand.Path } catch { $dir = $null }
        }
        if (-not $dir) { return $null }
        return (Split-Path -Parent $dir)
    }

    function Get-Repo {
        param([Parameter(Mandatory = $true)][string] $Root)

        if ($env:NEXSHELL_REPO) { return $env:NEXSHELL_REPO.Trim() }

        $p = Join-Path $Root '.nexshell_repo'
        if (-not (Test-Path -Path $p)) { return $null }
        $v = (Get-Content -Path $p -ErrorAction SilentlyContinue | Select-Object -First 1)
        if (-not $v) { return $null }
        $r = $v.Trim()
        if ($r.Length -eq 0) { return $null }
        return $r
    }

    function Get-UpdateChannel {
        param([Parameter(Mandatory = $true)][string] $Root)

        $defaultValue = 'stable'
        $cfg = Join-Path $Root 'config.toml'
        try { if (-not (Test-Path -Path $cfg)) { return $defaultValue } } catch { return $defaultValue }

        try {
            $lines = Get-Content -Path $cfg -ErrorAction Stop
        }
        catch {
            return $defaultValue
        }

        foreach ($line in @($lines)) {
            if ($null -eq $line) { continue }
            $m = [Regex]::Match(
                $line,
                '^\s*update_channel\s*=\s*"(stable|beta|nightly)"\s*(#.*)?$',
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
            )
            if ($m.Success) {
                return $m.Groups[1].Value.ToLower()
            }
        }

        return $defaultValue
    }

    function Get-ReleaseForChannel {
        param(
            [Parameter(Mandatory = $true)][string] $Repo,
            [Parameter(Mandatory = $true)][string] $Channel
        )

        if (-not (Get-Command -Name Invoke-RestMethod -ErrorAction SilentlyContinue) -and -not (Get-Command -Name Invoke-WebRequest -ErrorAction SilentlyContinue)) {
            throw 'upd requires PowerShell 3+ (Invoke-RestMethod/Invoke-WebRequest)'
        }

        $uri = "https://api.github.com/repos/$Repo/releases"
        $headers = @{ 'User-Agent' = 'NexShell' }

        try {
            if (Get-Command -Name Invoke-RestMethod -ErrorAction SilentlyContinue) {
                $releases = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
            }
            else {
                $raw = Invoke-WebRequest -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
                if (-not $raw -or -not $raw.Content) { return $null }
                if (-not (Get-Command -Name ConvertFrom-Json -ErrorAction SilentlyContinue)) { return $null }
                $releases = $raw.Content | ConvertFrom-Json
            }
        }
        catch {
            return $null
        }

        if (-not $releases) { return $null }

        $channel = $Channel.ToLower().Trim()
        if (-not $channel) { $channel = 'stable' }

        if ($channel -eq 'stable') {
            return $releases | Where-Object { -not $_.prerelease } | Select-Object -First 1
        }

        $match = $releases | Where-Object { $_.prerelease } | Where-Object {
            ($_.tag_name -match $channel) -or ($_.name -match $channel)
        } | Select-Object -First 1
        if ($match) { return $match }

        return $releases | Where-Object { $_.prerelease } | Select-Object -First 1
    }

    function Expand-ZipTo {
        param(
            [Parameter(Mandatory = $true)][string] $ZipPath,
            [Parameter(Mandatory = $true)][string] $Destination
        )

        try {
            if (Get-Command -Name Expand-Archive -ErrorAction SilentlyContinue) {
                Expand-Archive -Path $ZipPath -DestinationPath $Destination -Force
                return
            }

            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop | Out-Null
            [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $Destination)
        }
        catch {
            # Fallback to shell
            try {
                $shell = New-Object -ComObject Shell.Application
                $zipNs = $shell.NameSpace($ZipPath)
                if (-not $zipNs) { throw 'Unable to open zip file for extraction.' }
                $destNs = $shell.NameSpace($Destination)
                if (-not $destNs) { throw 'Unable to open destination folder for extraction.' }
                $destNs.CopyHere($zipNs.Items(), 0x10)
            }
            catch {
                throw ("failed to extract zip: {0}" -f $_.Exception.Message)
            }
        }
    }

    $tmp = $null
    try {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

        $root = Get-InstallRoot
        if (-not $root) { throw 'unable to find install root.' }

        $repo = Get-Repo -Root $root
        if (-not $repo) { throw "unable to find repo configuration. Set `$env:NEXSHELL_REPO or create '$($root)\\.nexshell_repo' with 'owner/repo'." }

        $channel = if ($Channel) { $Channel.Trim().ToLower() } else { Get-UpdateChannel -Root $root }
        if (-not $channel) { $channel = 'stable' }

        $release = Get-ReleaseForChannel -Repo $repo -Channel $channel
        if (-not $release) { throw "unable to find latest release for channel '$channel'." }

        $tag = $release.tag_name
        if (-not $tag) { throw 'release missing tag name.' }
        $zipUrl = $release.zipball_url
        if (-not $zipUrl) { throw 'release missing zipball_url.' }

        $localPath = Join-Path $root '.nexshell.sha'
        $local = $null
        if (Test-Path -Path $localPath) {
            $local = (Get-Content -Path $localPath -ErrorAction SilentlyContinue | Select-Object -First 1)
        }
        if ($local) { $local = $local.Trim() }

        $localKey = "${channel}:${tag}"
        if ($local -and ($local -eq $localKey) -and (-not $Force)) {
            return
        }

        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('NexShell-' + [Guid]::NewGuid().ToString('N'))
        $zip = Join-Path $tmp 'repo.zip'
        $extract = Join-Path $tmp 'extract'
        New-Item -ItemType Directory -Path $extract -Force | Out-Null

        $headers = @{ 'User-Agent' = 'NexShell' }
        try {
            Invoke-WebRequest -Uri $zipUrl -Headers $headers -OutFile $zip -UseBasicParsing -ErrorAction Stop | Out-Null
        }
        catch {
            Invoke-WebRequest -Uri $zipUrl -Headers $headers -OutFile $zip -ErrorAction Stop | Out-Null
        }

        Expand-ZipTo -ZipPath $zip -Destination $extract

        $repoRoot = Get-ChildItem -Path $extract -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $repoRoot) { throw 'downloaded archive did not contain a root folder.' }

        $newProfile = Join-Path $repoRoot.FullName 'Microsoft.PowerShell_profile.ps1'
        $newMain = Join-Path $repoRoot.FullName 'main.ps1'
        $newInstaller = Join-Path $repoRoot.FullName 'installer.ps1'
        $newFns = Join-Path $repoRoot.FullName 'fns'

        foreach ($req in @($newProfile, $newMain, $newFns)) {
            if (-not (Test-Path -Path $req)) { throw ("Update package missing: {0}" -f $req) }
        }

        foreach ($p in @(
            (Join-Path $root 'Microsoft.PowerShell_profile.ps1'),
            (Join-Path $root 'main.ps1'),
            (Join-Path $root 'installer.ps1'),
            (Join-Path $root 'fns')
        )) {
            if (Test-Path -Path $p) { Remove-Item -Path $p -Recurse -Force }
        }

        Copy-Item -Path $newProfile -Destination (Join-Path $root 'Microsoft.PowerShell_profile.ps1') -Force
        Copy-Item -Path $newMain -Destination (Join-Path $root 'main.ps1') -Force
        if (Test-Path -Path $newInstaller) {
            Copy-Item -Path $newInstaller -Destination (Join-Path $root 'installer.ps1') -Force
        }
        Copy-Item -Path $newFns -Destination (Join-Path $root 'fns') -Recurse -Force

        ($localKey.Trim() + "`r`n") | Set-Content -Path $localPath -Encoding UTF8 -Force
    }
    catch {
        Write-Error -Message $_.Exception.Message -ErrorAction Continue
        $msg = $_.Exception.Message
        if ($msg -match 'connect to the remote server|network|TLS|certificate') {
            Write-Host 'hint: this needs internet access to github (and may require tls 1.2 / proxy settings on older systems)'
        }
    }
    finally {
        try {
            if ($tmp -and (Test-Path -Path $tmp)) { Remove-Item -Path $tmp -Recurse -Force }
        }
        catch { }
    }
}

