<#
Do not edit unless you understand PowerShell scoping and command resolution.
`which` helps answer: "What will run if I type this command?"
#>

function which {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('Command', 'CommandName', 'Name')]
        [string[]] $InputObject,

        [Alias('a')]
        [switch] $All
    )

    begin {
        $getCommandSupportsAll = $false
        try {
            $gc = Get-Command -Name 'Get-Command' -ErrorAction Stop
            if ($gc -and $gc.Parameters -and $gc.Parameters.ContainsKey('All')) {
                $getCommandSupportsAll = $true
            }
        }
        catch {
            $getCommandSupportsAll = $false
        }

        function Get-WhichPathMatches {
            param([Parameter(Mandatory = $true)][string] $CommandName)

            $results = @()

            # If the user passed a path, do not search PATH.
            if ($CommandName -match '[\\/]' -or ($CommandName.Length -ge 2 -and $CommandName[1] -eq ':')) {
                return @()
            }

            $pathValue = $env:PATH
            if (-not $pathValue) { return @() }

            $pathExtValue = $env:PATHEXT
            $extensions = @()

            $hasExtension = $false
            try { $hasExtension = ([System.IO.Path]::GetExtension($CommandName).Length -gt 0) } catch { $hasExtension = $false }

            if ($hasExtension) {
                $extensions = @('')
            }
            else {
                if ($pathExtValue) {
                    $extensions = @($pathExtValue -split ';' | Where-Object { $_ -and $_.Trim().Length -gt 0 })
                }
                if (-not $extensions -or $extensions.Count -eq 0) {
                    $extensions = @('.COM', '.EXE', '.BAT', '.CMD')
                }
            }

            $dirs = @($pathValue -split ';' | Where-Object { $_ -and $_.Trim().Length -gt 0 })
            foreach ($dirRaw in $dirs) {
                $dir = $dirRaw.Trim().Trim('"')
                if ($dir.Length -eq 0) { continue }

                try {
                    if (-not (Test-Path -Path $dir)) { continue }
                }
                catch {
                    continue
                }

                foreach ($ext in $extensions) {
                    $candidate = $null
                    try { $candidate = Join-Path $dir ($CommandName + $ext) } catch { $candidate = $null }
                    if (-not $candidate) { continue }

                    try {
                        if (Test-Path -Path $candidate -PathType Leaf) {
                            $results += $candidate
                        }
                    }
                    catch {
                        continue
                    }
                }
            }

            # De-duplicate, case-insensitive.
            $seen = @{}
            foreach ($p in $results) {
                if (-not $p) { continue }
                $k = $p.ToLower()
                if (-not $seen.ContainsKey($k)) {
                    $seen[$k] = $true
                    $p
                }
            }
        }
    }

    process {
        foreach ($rawName in $InputObject) {
            $name = $rawName
            if ($null -eq $name) { continue }
            $name = $name.Trim()

            if ($name.Length -eq 0) {
                Write-Error 'which: empty command name'
                continue
            }

            $cmds = $null
            try {
                if ($All -and $getCommandSupportsAll) {
                    $cmds = Get-Command -Name $name -All -ErrorAction Stop
                }
                else {
                    $cmds = Get-Command -Name $name -ErrorAction Stop
                }
            }
            catch {
                Write-Error ("which: command not found: {0}" -f $name)
                continue
            }

            if (-not $cmds) {
                Write-Error ("which: command not found: {0}" -f $name)
                continue
            }

            $alreadyOutputPaths = @{}

            $cmdList = @($cmds)
            if (-not $All) { $cmdList = @($cmdList)[0] }

            foreach ($cmd in @($cmdList)) {
                try {
                    # Prefer the real filesystem path when available (applications/scripts).
                    $pathProp = $cmd.PSObject.Properties['Path']
                    if ($pathProp -and $pathProp.Value) {
                        $p = [string] $pathProp.Value
                        $alreadyOutputPaths[$p.ToLower()] = $true
                        Write-Output $p
                        continue
                    }

                    # Alias: show the resolution target.
                    if ($cmd.CommandType -eq 'Alias') {
                        Write-Output ("Alias: {0} -> {1}" -f $cmd.Name, $cmd.Definition)
                        continue
                    }

                    # Function: show the defining file if known, otherwise just name/type.
                    if ($cmd.CommandType -eq 'Function') {
                        $file = $null
                        try {
                            if ($cmd.ScriptBlock -and $cmd.ScriptBlock.File) { $file = $cmd.ScriptBlock.File }
                        }
                        catch {
                            $file = $null
                        }

                        if ($file) {
                            Write-Output $file
                        }
                        else {
                            Write-Output ("Function: {0}" -f $cmd.Name)
                        }
                        continue
                    }

                    # Cmdlet: show module when known.
                    if ($cmd.CommandType -eq 'Cmdlet') {
                        $src = $null
                        try { $src = $cmd.Source } catch { $src = $null }

                        if ($src) {
                            Write-Output ("Cmdlet: {0} ({1})" -f $cmd.Name, $src)
                        }
                        else {
                            Write-Output ("Cmdlet: {0}" -f $cmd.Name)
                        }
                        continue
                    }

                    # Fallback: Definition is usually the best human-readable target.
                    if ($cmd.Definition) {
                        Write-Output $cmd.Definition
                    }
                    else {
                        Write-Output $cmd.Name
                    }
                }
                catch {
                    Write-Warning ("which: failed to format result for '{0}': {1}" -f $name, $_.Exception.Message)
                }
            }

            # Best-effort PATH search for older PowerShell versions that lack `Get-Command -All`.
            if ($All -and (-not $getCommandSupportsAll)) {
                foreach ($p in @(Get-WhichPathMatches -CommandName $name)) {
                    $key = $p.ToLower()
                    if ($alreadyOutputPaths.ContainsKey($key)) { continue }
                    $alreadyOutputPaths[$key] = $true
                    Write-Output $p
                }
            }
        }
    }
}
