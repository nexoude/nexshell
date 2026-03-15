<#
Do not edit unless you understand what it does.
`chkupd` checks if an update is available.
#>

function chkupd {
    [CmdletBinding()]
    param()

    $ErrorActionPreference = 'Stop'

    function Write-InfoTable {
        param(
            [Parameter(Mandatory = $true)][hashtable] $Rows
        )

        $keys = @($Rows.Keys)
        if (-not $keys -or $keys.Count -eq 0) { return }

        $maxKey = ($keys | Measure-Object -Property Length -Maximum).Maximum
        foreach ($k in @($keys | Sort-Object)) {
            $v = $Rows[$k]
            if ($null -eq $v) { $v = '' }
            $label = ([string]$k).PadRight($maxKey)
            Write-Host ("{0}  {1}" -f $label, $v)
        }
    }

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
            if ($m.Success) { return $m.Groups[1].Value.ToLower() }
        }

        return $defaultValue
    }

    function Get-ReleaseForChannel {
        param(
            [Parameter(Mandatory = $true)][string] $Repo,
            [Parameter(Mandatory = $true)][string] $Channel
        )

        if (-not (Get-Command -Name Invoke-RestMethod -ErrorAction SilentlyContinue) -and -not (Get-Command -Name Invoke-WebRequest -ErrorAction SilentlyContinue)) {
            throw 'chkupd requires powershell 3+ (invoke-restmethod/invoke-webrequest)'
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

    try {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

        $root = Get-InstallRoot
        if (-not $root) { 
            Write-Error "Unable to determine installation directory. Ensure you're running from a properly installed NexShell profile. Run 'Get-Location' to check your current directory."
            return
        }

        $repo = Get-Repo -Root $root
        if (-not $repo) { 
            Write-Error "Repository not configured. Set `$env:NEXSHELL_REPO = 'owner/repo' or create '$($root)\.nexshell_repo' with 'owner/repo'. Run 'upd' to update or reinstall."
            return
        }

        $channel = Get-UpdateChannel -Root $root
        $release = Get-ReleaseForChannel -Repo $repo -Channel $channel
        if (-not $release) { 
            Write-Error "Unable to check for updates (network or API failure) for channel '$channel'. Check your internet connection. Run 'upd -Channel $channel' to attempt update anyway."
            return
        }

        $tag = $release.tag_name
        if (-not $tag) { 
            Write-Error "Release is missing tag name. This may indicate an issue with the repository. Try again later."
            return
        }

        $localPath = Join-Path $root '.nexshell.sha'
        $local = $null
        if (Test-Path -Path $localPath) {
            $local = (Get-Content -Path $localPath -ErrorAction SilentlyContinue | Select-Object -First 1)
        }
        if ($local) { $local = $local.Trim() }

        $localKey = "${channel}:${tag}"

        if (-not $local) {
            Write-InfoTable -Rows @{
                Installed = 'unknown'
                Latest    = $localKey
                Status    = 'unknown (no local .nexshell.sha)'
            }
            return
        }

        if ($local -eq $localKey) {
            Write-InfoTable -Rows @{
                Installed = $local
                Latest    = $localKey
                Status    = 'up to date'
            }
        }
        else {
            Write-InfoTable -Rows @{
                Installed = $local
                Latest    = $localKey
                Status    = 'update available'
            }
        }
    }
    catch {
        Write-Error -Message "Check update failed: $($_.Exception.Message)" -ErrorAction Continue
        $msg = $_.Exception.Message
        if ($msg -match 'connect to the remote server|network|TLS|certificate') {
            Write-Host 'Hint: This requires internet access to GitHub. Ensure TLS 1.2 is enabled and check proxy settings. Run "upd" to attempt an update.'
        } elseif ($msg -match 'access denied|permission|unauthorized') {
            Write-Host 'Hint: Permission denied. Ensure you have read access to the installation directory.'
        } else {
            Write-Host 'Hint: If you are stuck, run "upd -Force" to force an update or check the repository configuration.'
        }
    }
}

