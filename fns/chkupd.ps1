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

    function Get-LatestSha {
        param([Parameter(Mandatory = $true)][string] $Repo)

        if (-not (Get-Command -Name Invoke-RestMethod -ErrorAction SilentlyContinue) -and -not (Get-Command -Name Invoke-WebRequest -ErrorAction SilentlyContinue)) {
            throw 'chkupd requires powershell 3+ (invoke-restmethod/invoke-webrequest)'
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

    function Get-CompareInfo {
        param(
            [Parameter(Mandatory = $true)][string] $Repo,
            [Parameter(Mandatory = $true)][string] $BaseSha,
            [Parameter(Mandatory = $true)][string] $HeadSha
        )

        $uri = "https://api.github.com/repos/$Repo/compare/$BaseSha...$HeadSha"
        $headers = @{ 'User-Agent' = 'NexShell' }

        try {
            if (Get-Command -Name Invoke-RestMethod -ErrorAction SilentlyContinue) {
                return Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
            }

            $raw = Invoke-WebRequest -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
            if (-not $raw -or -not $raw.Content) { return $null }
            if (-not (Get-Command -Name ConvertFrom-Json -ErrorAction SilentlyContinue)) { return $null }
            return $raw.Content | ConvertFrom-Json
        }
        catch {
            return $null
        }
    }

    try {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

        $root = Get-InstallRoot
        if (-not $root) { throw 'unable to find install root' }

        $repo = Get-Repo -Root $root
        if (-not $repo) { throw "repo is not configured. set `$env:nexshell_repo or create '$($root)\\.nexshell_repo' with 'owner/repo'" }

        $latest = Get-LatestSha -Repo $repo
        if (-not $latest) { throw 'unable to check latest version (network/api failure)' }

        $localPath = Join-Path $root '.nexshell.sha'
        $local = $null
        if (Test-Path -Path $localPath) {
            $local = (Get-Content -Path $localPath -ErrorAction SilentlyContinue | Select-Object -First 1)
        }
        if ($local) { $local = $local.Trim() }

        if (-not $local) {
            Write-InfoTable -Rows @{
                Installed = 'unknown'
                Latest    = $latest.Substring(0, 12)
                Status    = 'unknown (no local .nexshell.sha)'
            }
            return
        }

        if ($local -eq $latest) {
            Write-InfoTable -Rows @{
                Installed = $local.Substring(0, 12)
                Latest    = $latest.Substring(0, 12)
                Status    = 'up to date'
            }
        }
        else {
            $status = 'update available'
            $detail = $null

            $cmp = Get-CompareInfo -Repo $repo -BaseSha $local -HeadSha $latest
            if ($cmp -and $cmp.status) {
                switch ($cmp.status) {
                    'behind' { $status = 'update available'; $detail = "remote is $($cmp.behind_by) commits ahead" }
                    'ahead'  { $status = 'local ahead'; $detail = "remote is $($cmp.behind_by) commits behind" }
                    'diverged' { $status = 'diverged'; $detail = "ahead by $($cmp.ahead_by), behind by $($cmp.behind_by)" }
                    default { $status = 'update available' }
                }
            }

            $rows = @{
                Installed = $local.Substring(0, 12)
                Latest    = $latest.Substring(0, 12)
                Status    = $status
            }
            if ($detail) { $rows['Detail'] = $detail }
            Write-InfoTable -Rows $rows
        }
    }
    catch {
        Write-Error -Message $_.Exception.Message -ErrorAction Continue
        $msg = $_.Exception.Message
        if ($msg -match 'connect to the remote server|network|TLS|certificate') {
            Write-Host 'hint: this needs internet access to github (and may require tls 1.2 / proxy settings on older systems)'
        }
    }
}

