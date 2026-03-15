<#
Checks for deprecated configuration keys (currently: auto_update) and offers to remove them.
#>

function Remove-DeprecatedAutoUpdate {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ConfigPath
    )

    if (-not (Test-Path -Path $ConfigPath)) { return }

    # Avoid prompting when running in non-interactive environments (CI, scripts).
    try {
        if ([Console]::IsInputRedirected) { return }
    }
    catch {
        # ignore environments where Console isn't available
    }

    $lines = Get-Content -Path $ConfigPath -ErrorAction SilentlyContinue
    if (-not $lines) { return }

    $hasAutoUpdate = $false
    foreach ($line in $lines) {
        if ($null -eq $line) { continue }
        if ($line -match '^[ \t]*auto_update\s*=') {
            $hasAutoUpdate = $true
            break
        }
    }

    if (-not $hasAutoUpdate) { return }

    Write-Host 'WARNING: `auto_update` is deprecated and will no longer be used.'
    Write-Host 'It is safe to remove it from your `config.toml`.'

    while ($true) {
        $ans = Read-Host 'Remove `auto_update` from config.toml now? (y/n)'
        if ($null -eq $ans) { continue }
        $a = $ans.Trim().ToLower()
        if ($a -in @('y', 'yes')) {
            $new = $lines | Where-Object { -not ($_ -match '^[ \t]*auto_update\s*=') }
            try {
                $new | Set-Content -Path $ConfigPath -Encoding UTF8
                Write-Host 'Removed `auto_update` from config.toml.'
            }
            catch {
                Write-Warning "Failed to update config.toml: $($_.Exception.Message)"
            }
            break
        }
        if ($a -in @('n', 'no')) {
            Write-Host 'Keeping `auto_update` in config.toml (deprecated).'
            break
        }

        Write-Host "Please enter 'y' or 'n'."
    }
}

# If this file is dot-sourced, the caller provides the config path.
if ($PSCommandPath) {
    # Script was run directly; use the current directory if possible.
    $root = Split-Path -Parent $PSCommandPath
    $cfg = Join-Path $root 'config.toml'
    Remove-DeprecatedAutoUpdate -ConfigPath $cfg
}
