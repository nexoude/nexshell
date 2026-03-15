try {
    if (Get-Module -Name Terminal-Icons -ListAvailable) {
        Write-Host "module 'terminal-icons' is reported as installed, attempting to import..."
        Import-Module Terminal-Icons
    }
    else {
        Write-Host "module 'terminal-icons' is not installed"
        Write-Host "checking for internet connection..."
        try {
            $networkAdapters = Get-CimInstance -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled = 'true'"
            if ($networkAdapters.Count -gt 0) {
                Write-Host "network connection detected, attempting to install 'terminal-icons' module..."
                Install-Module Terminal-Icons -Scope CurrentUser -Force
                Import-Module Terminal-Icons
            }
            else {
                Write-Host "no network detected, 'install-module' requires internet connection, skipping"
            }
        }
        catch {
            Write-Warning ("failed to check network or install module: {0}" -f $_.Exception.Message)
        }
    }
}
catch {
    Write-Warning ("Error in ls_icons.ps1: {0}" -f $_.Exception.Message)
}
