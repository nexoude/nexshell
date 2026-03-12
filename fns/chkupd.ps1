<#
Do not edit unless you understand what it does.
`chkupd` checks if an update is available.
#>

function chkupd {
    [CmdletBinding()]
    param()

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

    function Get-LatestSha {
        param([Parameter(Mandatory = $true)][string] $Repo)

        if (-not (Get-Command -Name Invoke-RestMethod -ErrorAction SilentlyContinue) -and -not (Get-Command -Name Invoke-WebRequest -ErrorAction SilentlyContinue)) {
            throw 'chkupd requires PowerShell 3+ (Invoke-RestMethod/Invoke-WebRequest).'
        }

        $uri = "https://api.github.com/repos/$Repo/commits/main"
        $headers = @{ 'User-Agent' = 'NexShell' }

        if (Get-Command -Name Invoke-RestMethod -ErrorAction SilentlyContinue) {
            $resp = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
            if ($resp -and $resp.sha) { return [string] $resp.sha }
        }

        $raw = Invoke-WebRequest -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
        if (-not $raw -or -not $raw.Content) { return $null }
        if (-not (Get-Command -Name ConvertFrom-Json -ErrorAction SilentlyContinue)) { return $null }
        $obj = $raw.Content | ConvertFrom-Json
        if ($obj -and $obj.sha) { return [string] $obj.sha }
        return $null
    }

    try {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

        $root = Get-InstallRoot
        if (-not $root) { throw 'Unable to find install root.' }

        $repo = Get-Repo -Root $root
        if (-not $repo) { throw "Repo is not configured. Set `$env:NEXSHELL_REPO or create '$($root)\\.nexshell_repo' with 'owner/repo'." }

        $latest = Get-LatestSha -Repo $repo
        if (-not $latest) { throw 'Unable to check latest version (network/API failure).' }

        $localPath = Join-Path $root '.nexshell.sha'
        $local = $null
        if (Test-Path -Path $localPath) {
            $local = (Get-Content -Path $localPath -ErrorAction SilentlyContinue | Select-Object -First 1)
        }
        if ($local) { $local = $local.Trim() }

        if (-not $local) {
            Write-Host ("Installed version: unknown. Latest: {0}" -f $latest.Substring(0, 12)) -ForegroundColor Yellow
            return
        }

        if ($local -eq $latest) {
            Write-Host 'Up to date.' -ForegroundColor Green
        }
        else {
            Write-Host ("Update available: {0} -> {1}" -f $local.Substring(0, 12), $latest.Substring(0, 12)) -ForegroundColor Yellow
        }
    }
    catch {
        Write-Error -Message $_.Exception.Message -ErrorAction Continue
        $msg = $_.Exception.Message
        if ($msg -match 'connect to the remote server|network|TLS|certificate') {
            Write-Host 'Hint: this needs internet access to GitHub (and may require TLS 1.2 / proxy settings on older systems).' -ForegroundColor Yellow
        }
    }
}

