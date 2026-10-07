<#
.SYNOPSIS
  ТЗ-6. Одна команда обновления модуля Диадок на новую версию вендора.
  Версия: 1.1 · 07.10.2026 · Windows PowerShell 5.1+

.DESCRIPTION
  Шаги: 1 Подготовка → 2 Сверка прода → 3 Импорт вендора → 4 Слияние → 5 Проверки → 6 Сборка → 7 Журнал.
  Останавливается на первой проблеме и пишет, что делать. Прод НЕ трогает (загрузка в прод — руками по регламенту).
  -DryRun   — шаги 1–5 (ранний прогон на каждом релизе вендора), ветка update/<версия> потом удаляется.
  -From N   — продолжить с шага N (например, после ручного разбора конфликтов: -From 5).
  Коды возврата: 0 — МОЖНО СТАВИТЬ (или DryRun пройден); 1 — СТОП по содержанию; 2 — сбой скрипта.
.EXAMPLE
  $env:DIADOC_IB_PASSWORD = '...'
  powershell -NoProfile -File tools\update.ps1 -Cfe D:\Диадок\KonturDiadok_4.62.0.cfe -Version 4.62.0 -DryRun
#>
param(
    [Parameter(Mandatory = $true)] [string] $Version,
    [string] $Cfe = '',
    [switch] $DryRun,
    [ValidateRange(1, 7)] [int] $From = 1,
    [string] $Config = (Join-Path $PSScriptRoot 'update.config.psd1'),
    [string] $ReleaseType = ''
)
. (Join-Path $PSScriptRoot 'lib\common.ps1')
Set-StrictMode -Version Latest

$root = Get-RepoRoot
$outDir = Join-Path $root ("out\" + $Version)
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$logFile = Join-Path $outDir 'log.txt'
$timings = [ordered]@{}
$state = @{ Conflicts = 0; ConflictIds = ''; Violations = 0 }

function Write-Log([string] $Text) {
    $line = (Get-Date -Format 'HH:mm:ss') + '  ' + $Text
    Write-Host $line
    [System.IO.File]::AppendAllText($logFile, $line + "`r`n", $script:Utf8NoBom)
}
function Stop-Update([string] $Reason) { Write-Log "СТОП: $Reason"; Pop-Location; exit 1 }
function Invoke-Step([int] $N, [string] $Name, [scriptblock] $Body) {
    if ($N -lt $From) { Write-Log "Шаг $N. $Name — пропущен (-From $From)"; return }
    Write-Log "Шаг $N. $Name — начало"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $Body
    $sw.Stop(); $timings["$N. $Name"] = [Math]::Round($sw.Elapsed.TotalMinutes, 1)
    Write-Log ("Шаг $N. $Name — готово за {0} мин" -f $timings["$N. $Name"])
}
function New-Worktree([string] $Ref) {
    $wt = Join-Path ([System.IO.Path]::GetTempPath()) ('diadoc-wt-' + [guid]::NewGuid().ToString('N'))
    Invoke-Git worktree add --detach $wt $Ref | Out-Null
    return $wt
}
function Remove-Worktree([string] $Path) { & git worktree remove --force $Path 2>&1 | Out-Null }
function Test-Ref([string] $Ref) { & git rev-parse --verify --quiet $Ref 2>&1 | Out-Null; return ($LASTEXITCODE -eq 0) }

try {
    Push-Location $root
    $cfg = Import-UpdateConfig $Config
    $ext = $cfg.ExtensionName; $src = $cfg.SourceDir; $main = $cfg.MainBranch; $vend = $cfg.VendorBranch
    $vendorTag = "vendor/$Version"; $updBranch = "update/$Version"
    Write-Log "=== Обновление на $Version (DryRun: $DryRun, с шага $From) ==="

    Invoke-Step 1 'Подготовка' {
        if (@(& git status --porcelain).Count -gt 0) { Stop-Update 'в рабочей папке git есть незакоммиченные изменения — закоммитьте или уберите их' }
        foreach ($b in @($main, $vend)) { if (-not (Test-Ref $b)) { Stop-Update "нет ветки $b — сначала выполните ТЗ-1" } }
        if (-not (Test-Path -LiteralPath $cfg.OneCExe)) { Stop-Update "не найден 1cv8.exe: $($cfg.OneCExe)" }
        if ($cfg.ContainsKey('PlatformVersion') -and $cfg.PlatformVersion) {
            $fv = (Get-Item -LiteralPath $cfg.OneCExe).VersionInfo.FileVersion
            if ($fv -and ($fv -replace ',', '.' -replace ' ', '') -ne $cfg.PlatformVersion) { Stop-Update "версия платформы $fv ≠ записанной в настройках $($cfg.PlatformVersion) (выгрузки должны делаться одной версией)" }
        }
        if (-not (Test-Ref $vendorTag) -and ($Cfe -eq '' -or -not (Test-Path -LiteralPath $Cfe))) { Stop-Update "не задан или не найден файл новой версии вендора (-Cfe)" }
    }

    Invoke-Step 2 'Сверка прода с последним релизом' {
        $last = (& git describe --tags --match 'release/*' --abbrev=0 $main 2>$null)
        if (-not $last) { Write-Log 'Релизов ещё не было — сверка пропущена (первое обновление по новой схеме).'; return }
        $dump = Join-Path $outDir 'prod-dump'
        if (Test-Path -LiteralPath $dump) { Remove-Item -LiteralPath $dump -Recurse -Force }
        if ($cfg.ContainsKey('ProdCopyIb') -and $cfg.ProdCopyIb) {
            $r = Invoke-Designer $cfg 'ProdCopyIb' @('/DumpConfigToFiles', ('"' + $dump + '"'), '-Extension', $ext) $outDir
            Assert-DesignerOk $r 'Выгрузка расширения из копии прода'
        }
        elseif ($cfg.ContainsKey('ProdCfe') -and $cfg.ProdCfe) {
            $r = Invoke-Designer $cfg 'ServiceIb' @('/LoadCfg', ('"' + $cfg.ProdCfe + '"'), '-Extension', $ext) $outDir; Assert-DesignerOk $r 'Загрузка .cfe прода в служебную базу'
            $r = Invoke-Designer $cfg 'ServiceIb' @('/DumpConfigToFiles', ('"' + $dump + '"'), '-Extension', $ext) $outDir; Assert-DesignerOk $r 'Выгрузка'
        }
        else { Stop-Update 'в настройках не задан ни ProdCopyIb, ни ProdCfe — сверить прод нечем' }
        $wt = New-Worktree $last
        try { $d = Compare-Dumps (Join-Path $wt $src) $dump } finally { Remove-Worktree $wt }
        if ($d.Count -gt 0) {
            [System.IO.File]::WriteAllText((Join-Path $outDir 'prod-diff.txt'), ($d -join "`r`n"), $script:Utf8NoBom)
            Stop-Update "прод отличается от релиза $last ($($d.Count) файлов, список — prod-diff.txt). Кто-то правил прод мимо git: оформите эту правку в git и повторите"
        }
        Write-Log "Прод совпадает с $last."
    }

    Invoke-Step 3 'Импорт новой версии вендора в ветку vendor' {
        if (Test-Ref $vendorTag) { Write-Log "Тег $vendorTag уже есть — импорт пропущен."; return }
        $dump = Join-Path $outDir 'vendor-dump'
        if (Test-Path -LiteralPath $dump) { Remove-Item -LiteralPath $dump -Recurse -Force }
        $r = Invoke-Designer $cfg 'ServiceIb' @('/LoadCfg', ('"' + $Cfe + '"'), '-Extension', $ext) $outDir; Assert-DesignerOk $r 'Загрузка .cfe вендора в служебную базу'
        $r = Invoke-Designer $cfg 'ServiceIb' @('/DumpConfigToFiles', ('"' + $dump + '"'), '-Extension', $ext) $outDir; Assert-DesignerOk $r 'Выгрузка дистрибутива в файлы'
        $wt = Join-Path ([System.IO.Path]::GetTempPath()) ('diadoc-wt-' + [guid]::NewGuid().ToString('N'))
        Invoke-Git worktree add $wt $vend | Out-Null
        try {
            $target = Join-Path $wt $src
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
            New-Item -ItemType Directory -Path $target -Force | Out-Null
            Copy-Item -Path (Join-Path $dump '*') -Destination $target -Recurse
            Push-Location $wt
            Invoke-Git add -A -- $src | Out-Null
            $pv = if ($cfg.ContainsKey('PlatformVersion') -and $cfg.PlatformVersion) { $cfg.PlatformVersion } else { 'не указана в настройках' }
            Invoke-Git commit -q -m "vendor $Version (выгрузка платформой $pv)" | Out-Null
            Invoke-Git tag $vendorTag | Out-Null
            Pop-Location
        }
        finally { Remove-Worktree $wt }
        Write-Log "Снимок вендора $Version записан в ветку $vend, тег $vendorTag."
    }

    Invoke-Step 4 'Слияние новой версии вендора с нашими правками' {
        if (Test-Ref $updBranch) { Invoke-Git checkout -q $updBranch | Out-Null } else { Invoke-Git checkout -q -b $updBranch $main | Out-Null }
        & git merge-base --is-ancestor $vendorTag HEAD 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Log 'Версия вендора уже слита в эту ветку.'; return }
        & git merge --no-ff --no-edit -m "Слияние $vendorTag" $vendorTag 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $files = @(& git diff --name-only --diff-filter=U | Where-Object { $_ })
            $rep = New-Object System.Collections.Generic.List[string]
            $rep.Add("# Конфликты слияния $vendorTag"); $rep.Add(''); $rep.Add('| Файл | Конфликтных мест | Метки ШХ рядом |'); $rep.Add('|---|---|---|')
            $allIds = New-Object System.Collections.Generic.HashSet[string]; $hunks = 0
            foreach ($f in $files) {
                $t = [System.IO.File]::ReadAllText((Join-Path $root $f))
                $blocks = [regex]::Matches($t, '(?s)<<<<<<< .*?>>>>>>> [^\r\n]*')
                $ids = New-Object System.Collections.Generic.HashSet[string]
                foreach ($b in $blocks) { foreach ($m in [regex]::Matches($b.Value, '(?i)ШХ\s+(\d{2}-\d{2})')) { [void]$ids.Add($m.Groups[1].Value); [void]$allIds.Add($m.Groups[1].Value) } }
                $hunks += $blocks.Count
                $rep.Add("| $f | $($blocks.Count) | $((@($ids) | Sort-Object) -join ', ') |")
            }
            $state.Conflicts = $hunks; $state.ConflictIds = (@($allIds) | Sort-Object) -join ', '
            $rep.Add(''); $rep.Add("Итого: $hunks; ID: $($state.ConflictIds)")
            [System.IO.File]::WriteAllText((Join-Path $outDir 'conflicts.md'), ($rep -join "`r`n"), $script:Utf8NoBom)
            Stop-Update "конфликты слияния: $hunks мест в $($files.Count) файлах (список — conflicts.md). Разберите по регламенту (ТЗ-7 §4), закоммитьте и запустите снова с -From 5"
        }
        Write-Log 'Слияние прошло без конфликтов.'
    }

    Invoke-Step 5 'Проверки' {
        $cur = (& git rev-parse --abbrev-ref HEAD)
        if ($cur -ne $updBranch) { Invoke-Git checkout -q $updBranch | Out-Null }
        if (@(& git diff --name-only --diff-filter=U).Count -gt 0) { Stop-Update 'остались неразрешённые конфликты — разрешите и закоммитьте' }
        $prev = (& git describe --tags --match 'vendor/*' --abbrev=0 "$vendorTag^" 2>$null)
        $wtNew = New-Worktree $vendorTag
        $wtPrev = if ($prev) { New-Worktree $prev } else { '' }
        try {
            $inv = @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'checks\invariants.ps1'), '-VendorDir', (Join-Path $wtNew $src), '-WorkDir', (Join-Path $root $src),
                     '-Registry', (Join-Path $root 'docs\Диадок_РеестрИзменений.md'), '-Out', (Join-Path $outDir 'checks.md'))
            $anch = Join-Path $PSScriptRoot 'checks\anchors.csv'; if (Test-Path -LiteralPath $anch) { $inv += @('-AnchorsFile', $anch) }
            if ($wtPrev) { $inv += @('-PrevVendorDir', (Join-Path $wtPrev $src)) }
            & (Get-Process -Id $PID).Path @inv | ForEach-Object { Write-Log "  $_" }
            $code = $LASTEXITCODE
        }
        finally { Remove-Worktree $wtNew; if ($wtPrev) { Remove-Worktree $wtPrev } }
        if ($code -eq 2) { throw 'сбой invariants.ps1' }
        if ($code -eq 1) { Stop-Update 'нарушения автоматических проверок — см. checks.md (Б4 — просмотреть обязательно, даже если нарушений нет)' }
        if ($cfg.ContainsKey('SkipOneCChecks') -and $cfg.SkipOneCChecks) { Write-Log 'Компиляция и эталоны пропущены (SkipOneCChecks) — только для отладки!'; return }
        & (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $PSScriptRoot 'checks\compile.ps1') -Config $Config | ForEach-Object { Write-Log "  $_" }
        if ($LASTEXITCODE -ne 0) { Stop-Update 'компиляция не прошла (см. лог выше)' }
        & (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $PSScriptRoot 'checks\reference.ps1') -Config $Config | ForEach-Object { Write-Log "  $_" }
        if ($LASTEXITCODE -ne 0) { Stop-Update 'эталонные XML отличаются — разберите: ошибка переноса или вендор изменил формат (тогда эталон обновляется осознанно, с записью в журнал)' }
    }

    if ($DryRun) {
        Invoke-Git checkout -q $main | Out-Null
        & git branch -D $updBranch 2>&1 | Out-Null
        Write-Log "РАННИЙ ПРОГОН ПРОЙДЕН: версия $Version сливается без конфликтов и проходит проверки. Ветка $updBranch удалена, тег $vendorTag оставлен."
        $timings.GetEnumerator() | ForEach-Object { Write-Log ("  {0}: {1} мин" -f $_.Key, $_.Value) }
        Pop-Location; exit 0
    }

    $cfeOut = Join-Path $outDir ("{0}_{1}.cfe" -f $ext, $Version)
    Invoke-Step 6 'Сборка .cfe и тег релиза' {
        # .cfe собирается из тестовой базы, куда исходники грузит compile.ps1 на шаге 5. Без него соберётся старое.
        if ($cfg.ContainsKey('SkipOneCChecks') -and $cfg.SkipOneCChecks) { Stop-Update 'SkipOneCChecks включён: тестовая база не загружена из git, собирать .cfe нельзя. Выключите параметр и запустите с -From 5' }
        $r = Invoke-Designer $cfg 'TestIb' @('/DumpCfg', ('"' + $cfeOut + '"'), '-Extension', $ext) $outDir; Assert-DesignerOk $r 'Сборка .cfe'
        $existing = @(& git tag --points-at HEAD --list "release/$Version-*")
        if ($existing.Count -gt 0) { Write-Log "Коммит уже помечен $($existing[0])."; return }
        $n = @(& git tag --list "release/$Version-*").Count + 1
        Invoke-Git tag "release/$Version-$n" | Out-Null
        Write-Log "Собрано: $cfeOut; тег release/$Version-$n."
    }

    Invoke-Step 7 'Журнал' {
        $j = Join-Path $root 'docs\update-journal.md'
        if (-not (Test-Path -LiteralPath $j)) {
            [System.IO.File]::WriteAllText($j, "# Журнал обновлений модуля Диадок`n`n| Дата | Версия | Тип релиза | Время по шагам, мин | Итого, мин | Конфликты (мест / ID) | Исполнитель |`n|---|---|---|---|---|---|---|`n", $script:Utf8NoBom)
        }
        $cf = Join-Path $outDir 'conflicts.md'
        if ($state.Conflicts -eq 0 -and (Test-Path -LiteralPath $cf)) {
            # Продолжение после ручного разбора (-From 5): число конфликтов берём из отчёта шага 4.
            $m = [regex]::Match([System.IO.File]::ReadAllText($cf), 'Итого: (\d+); ID: ([^\r\n]*)')
            if ($m.Success) { $state.Conflicts = [int]$m.Groups[1].Value; $state.ConflictIds = $m.Groups[2].Value }
        }
        $rt = $ReleaseType; if (-not $rt) { $rt = Read-Host 'Тип релиза (минор / форматы / мажор)' }
        $steps = ($timings.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value)" }) -join '; '
        $total = ($timings.Values | Measure-Object -Sum).Sum
        $row = "| $(Get-Date -Format 'dd.MM.yyyy') | $Version | $rt | $steps | $total | $($state.Conflicts) / $($state.ConflictIds) | $([Environment]::UserName) |"
        [System.IO.File]::AppendAllText($j, $row + "`n", $script:Utf8NoBom)
        Invoke-Git add -- $j | Out-Null
        Invoke-Git commit -q -m "журнал: обновление $Version" | Out-Null
    }

    Write-Log "МОЖНО СТАВИТЬ: $cfeOut. Дальше — по регламенту (ТЗ-7 §5): бэкап прода, загрузка, smoke. После установки слейте ветку $updBranch в $main."
    Pop-Location; exit 0
}
catch {
    try { Write-Log "СБОЙ: $($_.Exception.Message)" } catch { Write-Host "СБОЙ: $($_.Exception.Message)" }
    Pop-Location -ErrorAction SilentlyContinue
    exit 2
}
