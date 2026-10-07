<#
.SYNOPSIS
  ТЗ-1 §3.4. Ретро-прогон: пробное слияние версий вендора в основную ветку — сколько было бы конфликтов.
  Версия: 1.1 · 07.10.2026 · Windows PowerShell 5.1+ · ничего не меняет в ветках (работает во временной копии).
.EXAMPLE
  powershell -NoProfile -File tools\retro.ps1 -Tags vendor/4.62.0,vendor/4.63.0
#>
param(
    [string[]] $Tags = @(),
    [string] $Base = 'main',
    [string] $SourceDir = 'SRC/КонтурДиадок',
    [string] $Out = ''
)
. (Join-Path $PSScriptRoot 'lib\common.ps1')
try {
    $root = Get-RepoRoot
    Push-Location $root
    # Через powershell -File список «a,b» приходит одной строкой — разбираем сами.
    $Tags = @($Tags | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($Tags.Count -eq 0) { $Tags = @(Invoke-Git tag --list 'vendor/*' --sort=version:refname) }
    if ($Out -eq '') { $Out = Join-Path $root ('docs\retro-' + (Get-Date -Format 'yyyy-MM-dd') + '.md') }
    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($tag in $Tags) {
        $wt = Join-Path ([System.IO.Path]::GetTempPath()) ('retro-' + [guid]::NewGuid().ToString('N'))
        Invoke-Git worktree add --detach $wt $Base | Out-Null
        try {
            Push-Location $wt
            & git merge --no-commit --no-ff $tag 2>&1 | Out-Null
            $files = @(& git diff --name-only --diff-filter=U 2>$null | Where-Object { $_ })
            $hunks = 0; $ours = 0
            foreach ($f in $files) {
                $t = [System.IO.File]::ReadAllText((Join-Path $wt $f))
                $h = ([regex]::Matches($t, '(?m)^<<<<<<< ')).Count; $hunks += $h
                if ($t -match '(?i)шх') { $ours += $h }
            }
            & git merge --abort 2>&1 | Out-Null
            Pop-Location
            $rows.Add("| $tag | $($files.Count) | $hunks | $ours | $((($files | ForEach-Object { $_.Replace($SourceDir + '/', '') }) -join '<br>')) |")
            Write-Host "$tag`: файлов с конфликтами $($files.Count), конфликтных мест $hunks (в файлах с нашими правками $ours)"
        }
        finally { Pop-Location -ErrorAction SilentlyContinue; & git worktree remove --force $wt 2>&1 | Out-Null }
    }
    $text = @('# Ретро-прогон слияния версий вендора', '', "- Дата: $(Get-Date -Format 'dd.MM.yyyy HH:mm'); основа: ``$Base``", '',
              '| Версия | Файлов с конфликтами | Конфликтных мест | Из них в файлах с нашими правками | Файлы |', '|---|---|---|---|---|') + $rows
    [System.IO.File]::WriteAllText($Out, ($text -join "`n") + "`n", $script:Utf8NoBom)
    Write-Host "Отчёт: $Out"
    Pop-Location
    exit 0
}
catch { Write-Host "СБОЙ: $($_.Exception.Message)"; exit 2 }
