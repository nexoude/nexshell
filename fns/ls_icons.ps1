try {
    if (Get-Module -Name Terminal-Icons -ListAvailable) {
        Write-Host "Module 'Terminal-Icons' is reported as installed, attempting to import..."
        Import-Module Terminal-Icons
    }
    else {
        Write-Host "Module 'Terminal-Icons' is not installed"
        Write-Host "Checking for internet connection..."
        try {
            $networkAdapters = Get-CimInstance -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled = 'true'"
            if ($networkAdapters.Count -gt 0) {
                Write-Host "Network connection detected, attempting to install 'Terminal-Icons' module..."
                Install-Module Terminal-Icons -Scope CurrentUser -Force
                Import-Module Terminal-Icons
            }
            else {
                Write-Error "No network detected. 'Install-Module' requires internet connection. Run 'Install-Module Terminal-Icons -Scope CurrentUser' when connected."
            }
        }
        catch {
            Write-Error ("Failed to check network or install module: {0}. Try running 'Install-Module Terminal-Icons -Scope CurrentUser -Force' manually." -f $_.Exception.Message)
        }
    }
}
catch {
    Write-Error ("Error loading Terminal-Icons: {0}. Nerd icons will not be available. Run 'Install-Module Terminal-Icons -Scope CurrentUser' to install manually." -f $_.Exception.Message)
}
