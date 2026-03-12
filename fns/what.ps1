<#
Do not edit unless you understand what it does.
`what` is a tiny help tool for NexShell.
#>

function what {
    param([string] $Topic)

    function Write-HelpTable {
        param([Parameter(Mandatory = $true)][hashtable] $HelpMap)

        $rows = foreach ($k in @($HelpMap.Keys | Sort-Object)) {
            [pscustomobject]@{
                Command     = $k
                Description = $HelpMap[$k].short
            }
        }

        $cmdW = [Math]::Max(7, (($rows | ForEach-Object { $_.Command.Length } | Measure-Object -Maximum).Maximum))
        $descW = [Math]::Max(11, (($rows | ForEach-Object { $_.Description.Length } | Measure-Object -Maximum).Maximum))

        Write-Host (('{0}  {1}' -f 'Command'.PadRight($cmdW), 'Description'))
        Write-Host (('{0}  {1}' -f ('-' * $cmdW), ('-' * $descW)))
        foreach ($r in $rows) {
            Write-Host (('{0}  {1}' -f $r.Command.PadRight($cmdW), $r.Description))
        }
    }

    $help = @{
        lx     = @{
            short = 'compact directory listing (interactive)'
            long  = @(
                'lx prints a compact, columnar directory listing.',
                '',
                'Technicals:',
                '- Uses `Get-ChildItem -Force` (shows hidden files).',
                '- Uses `$Host.UI.RawUI.BufferSize.Width` to compute columns.',
                '- Appends "/" to directory names, prints dirs in Blue and files in White.',
                '- Uses `Write-Host`, so it is meant for interactive use (not pipelines).'
            )
        }
        which  = @{
            short = 'shows what a command resolves to'
            long  = @(
                'which answers: "what will run if I type this command?"',
                '',
                'Examples:',
                '- which git',
                '- which -a git   (show all matches when supported)',
                '',
                'Technicals:',
                '- Uses `Get-Command` and tries to print a real filesystem path when available.',
                '- On older PowerShell versions, it includes a best-effort PATH search fallback.'
            )
        }
        chkupd = @{
            short = 'checks if updates are available'
            long  = @(
                'chkupd checks GitHub to see if there is a newer NexShell version available.',
                '',
                'Notes:',
                '- Requires repo config via `$env:NEXSHELL_REPO` or a `.nexshell_repo` file.',
                '- Needs internet access to GitHub.'
            )
        }
        upd    = @{
            short = 'updates NexShell (no prompts)'
            long  = @(
                'upd downloads and installs the latest NexShell version from GitHub.',
                '',
                'Important:',
                '- It does NOT prompt for confirmations.',
                '- Requires repo config via `$env:NEXSHELL_REPO` or a `.nexshell_repo` file.',
                '- Needs internet access to GitHub.'
            )
        }
        what   = @{
            short = 'NexShell help tool'
            long  = @(
                '`what` is a help tool for NexShell.'
            )
        }
    }

    if (-not $Topic) {
        Write-HelpTable -HelpMap $help
        return
    }

    $t = @($Topic) + @($args)
    $t = @($t | Where-Object { $_ -ne $null } | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_.Length -gt 0 })
    if (-not $t -or $t.Count -eq 0) {
        Write-Host '`what` is a help tool for NexShell.'
        return
    }

    $allWhat = $true
    foreach ($x in $t) {
        if ($x.ToLower() -ne 'what') { $allWhat = $false; break }
    }

    # `what what what` (args: what, what) and beyond.
    if ($allWhat -and $t.Count -ge 2) {
        Write-Host 'motherfucker what are you doing'
        return
    }

    $key = $t[0].ToLower()
    if ($key -eq 'what') {
        Write-Host '`what` is a help tool for NexShell.'
        return
    }

    if (-not $help.ContainsKey($key)) {
        Write-Host ("No NexShell help for: {0}" -f $t[0])
        Write-Host "Run 'what' to see available NexShell commands."
        return
    }

    foreach ($line in @($help[$key].long)) {
        Write-Host $line
    }
}
