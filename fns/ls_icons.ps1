if (
    Get-Module -Name Terminal-Icons -ListAvailable
) {
    Write-Host "module 'terminal-icons' is reported as installed, attempting to import...";
    Import-Module Terminal-Icons 
}
else { 
    Write-Host "module 'terminal-icons' is not installed"
    Write-Host "checking for internet connection..."
    if (
        (Get-CimInstance -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled = 'true'").Count -gt 0
    ) {
        Write-Host "network connection detected, attempting to install 'terminal-icons' module..."
        Install-Module Terminal-Icons -Scope CurrentUser -Force
        Import-Module Terminal-Icons 
    }
    else {
        Write-Host "no network decected, 'install-module' requires internet connection, skipping"
    }
}
