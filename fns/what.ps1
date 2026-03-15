<#
Do not edit unless you understand what it does.
`what` is a tiny help tool for NexShell.
#>

function what {
    param()

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
                'lx prints a compact, columnar directory listing',
                '',
                'technicals:',
                '- uses `get-childitem -force` (shows hidden files)',
                '- uses `$host.ui.rawui.buffersize.width` to compute columns',
                '- appends "/" to directory names, prints dirs in blue and files in white',
                '- uses `write-host`, so it is meant for interactive use (not pipelines)'
            )
        }
        which  = @{
            short = 'shows what a command resolves to'
            long  = @(
                'which answers: "what will run if I type this command?"',
                '',
                'examples:',
                '- which git',
                '- which -a git   (show all matches when supported)',
                '',
                'technicals:',
                '- uses `get-command` and tries to print a real filesystem path when available',
                '- on older powershell versions, it includes a best-effort path search fallback'
            )
        }
        chkupd = @{
            short = 'checks if updates are available'
            long  = @(
                'chkupd checks github to see if there is a newer nexshell version available',
                '',
                'notes:',
                '- requires repo config via `$env:nexshell_repo` or a `.nexshell_repo` file',
                '- needs internet access to github'
            )
        }
        upd    = @{
            short = 'updates NexShell (no prompts)'
            long  = @(
                'upd downloads and installs the latest nexshell version from github',
                '',
                'important:',
                '- it does not prompt for confirmations',
                '- requires repo config via `$env:nexshell_repo` or a `.nexshell_repo` file',
                '- needs internet access to github'
            )
        }
        what   = @{
            short = 'nexshell help tool'
            long  = @(
                '`what` is a help tool for nexshell'
            )
        }
    }

    if (-not $args -or $args.Count -eq 0) {
        Write-HelpTable -HelpMap $help
        return
    }

    $t = $args
    $t = @($t | Where-Object { $_ -ne $null } | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_.Length -gt 0 })
    if (-not $t -or $t.Count -eq 0) {
        Write-Host '`what` is a help tool for nexshell'
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
        Write-Host '`what` is a help tool for nexshell'
        return
    }

    if (-not $help.ContainsKey($key)) {
        Write-Host ("no nexshell help for: {0}" -f $t[0])
        Write-Host "run 'what' to see available nexshell commands"
        return
    }

    foreach ($line in @($help[$key].long)) {
        Write-Host $line
    }
}
