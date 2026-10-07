# Generates App/Resources/Localizable.xcstrings (String Catalog) from Localization/strings.tsv.
# Edit the TSV (key<TAB>uk<TAB>ru<TAB>en), then run:  powershell -ExecutionPolicy Bypass -File scripts/gen-strings.ps1
$root = Split-Path -Parent $PSScriptRoot
$tsv = Join-Path $root "Localization/strings.tsv"
$out = Join-Path $root "App/Resources/Localizable.xcstrings"

function Esc([string]$s) {
    $s = $s.Replace('\n', "`n")
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        switch ($ch) {
            '"' { [void]$sb.Append('\"') }
            '\' { [void]$sb.Append('\\') }
            "`n" { [void]$sb.Append('\n') }
            "`t" { [void]$sb.Append('\t') }
            default { [void]$sb.Append($ch) }
        }
    }
    $sb.ToString()
}

$lines = Get-Content -Encoding UTF8 $tsv | Select-Object -Skip 1 | Where-Object { $_.Trim() -ne "" }
$rows = foreach ($line in $lines) {
    $p = $line.Split("`t")
    if ($p.Count -ne 4) { throw "Bad line (need 4 tab-separated columns: key, uk, ru, en): $line" }
    [pscustomobject]@{ Key = $p[0]; Uk = $p[1]; Ru = $p[2]; En = $p[3] }
}
$rows = $rows | Sort-Object Key -CaseSensitive

$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("{`n  `"sourceLanguage`" : `"uk`",`n  `"strings`" : {`n")
$i = 0
foreach ($r in $rows) {
    $i++
    $comma = if ($i -lt $rows.Count) { "," } else { "" }
    [void]$sb.Append("    `"$(Esc $r.Key)`" : {`n")
    [void]$sb.Append("      `"extractionState`" : `"manual`",`n")
    [void]$sb.Append("      `"localizations`" : {`n")
    [void]$sb.Append("        `"en`" : { `"stringUnit`" : { `"state`" : `"translated`", `"value`" : `"$(Esc $r.En)`" } },`n")
    [void]$sb.Append("        `"ru`" : { `"stringUnit`" : { `"state`" : `"translated`", `"value`" : `"$(Esc $r.Ru)`" } },`n")
    [void]$sb.Append("        `"uk`" : { `"stringUnit`" : { `"state`" : `"translated`", `"value`" : `"$(Esc $r.Uk)`" } }`n")
    [void]$sb.Append("      }`n    }$comma`n")
}
[void]$sb.Append("  },`n  `"version`" : `"1.0`"`n}`n")

New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
[System.IO.File]::WriteAllText($out, $sb.ToString(), (New-Object System.Text.UTF8Encoding $false))
Write-Output "Wrote $($rows.Count) strings to $out"
