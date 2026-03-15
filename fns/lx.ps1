<#
`lx` is a cleaner, faster alternative to `ls`.
Note that it uses Write-Host and not Write-Output,
so it won't work in pipelines. It's meant for interactive use only.
#>
function lx {
    [CmdletBinding()]
    param([string]$Path = '.')

    try {
        $width = $Host.UI.RawUI.BufferSize.Width
        $items = Get-ChildItem -Path $Path -Force -ErrorAction Stop |
        ForEach-Object { if ($_.PSIsContainer) { "$($_.Name)/" } else { $_.Name } }
    }
    catch {
        Write-Warning ("lx: failed to list directory '{0}': {1}" -f $Path, $_.Exception.Message)
        return
    }

    $items = @($items)

    if (-not $items -or $items.Count -eq 0) { return }

    $max = ($items | Measure-Object -Property Length -Maximum).Maximum
    $colWidth = $max + 2
    $numCols = [Math]::Max([Math]::Floor($width / $colWidth), 1)
    $numRows = [Math]::Ceiling($items.Count / $numCols)

    for ($row = 0; $row -lt $numRows; $row++) {
        for ($col = 0; $col -lt $numCols; $col++) {
            $idx = $col * $numRows + $row
            if ($idx -ge $items.Count) { continue }

            $name = $items[$idx]
            if ($name.EndsWith('/')) { $color = 'Blue' } else { $color = 'White' }
            $pad = if ($col -lt ($numCols - 1)) { $colWidth - $name.Length } else { 0 }

            Write-Host ($name.PadRight($name.Length + $pad)) -ForegroundColor $color -NoNewline
            Remove-Variable color -ErrorAction SilentlyContinue -Scope Local
        }
        Write-Host ''
    }

    Remove-Variable items, max, colWidth, numCols, numRows, width, row, col, idx, name, pad -ErrorAction SilentlyContinue -Scope Local
}
