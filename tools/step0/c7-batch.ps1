<#
.SYNOPSIS
  Шаг 0, сценарий С7 (Г6): проверить, что пакетный Конфигуратор умеет всё, что нужно update.ps1.
  Версия: 1.0 · 07.10.2026 · Windows PowerShell 5.1+ · ТОЛЬКО ТЕСТОВАЯ БАЗА (TestIb из настроек).

.DESCRIPTION
  Без -Run только печатает команды (ничего не запускает).
  С -Run выполняет по очереди и пишет итог по каждой команде:
    1 /DumpConfigToFiles  — выгрузка расширения в файлы (база не меняется);
    2 /LoadConfigFromFiles — загрузка тех же файлов обратно  ⚠️ перезаписывает расширение в тестовой базе;
    3 /UpdateDBCfg         — применение к базе             ⚠️ без бэкапа не откатить;
    4 /CheckModules        — синтаксическая проверка модулей;
    5 /DumpCfg             — сборка .cfe;
    6 /LoadCfg             — загрузка собранного .cfe       ⚠️ перезаписывает расширение;
    7 повторная выгрузка и сравнение с п. 1 — круг «выгрузил → загрузил → выгрузил» без потерь.
  Перед -Run сделайте копию тестовой базы. Итог — out\step0-c7\result.md, перенесите в ТЗ-0 §6.
.EXAMPLE
  $env:DIADOC_IB_PASSWORD = '...'
  powershell -NoProfile -File tools\step0\c7-batch.ps1 -Config tools\update.config.psd1        # показать команды
  powershell -NoProfile -File tools\step0\c7-batch.ps1 -Config tools\update.config.psd1 -Run   # выполнить
#>
param(
    [string] $Config = (Join-Path $PSScriptRoot '..\update.config.psd1'),
    [switch] $Run
)
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
try {
    $cfg = Import-UpdateConfig $Config
    $root = Get-RepoRoot
    $ext = $cfg.ExtensionName
    $dir = Join-Path $root 'out\step0-c7'
    $d1 = Join-Path $dir 'dump1'; $d2 = Join-Path $dir 'dump2'; $cfe = Join-Path $dir ($ext + '_c7.cfe')
    $steps = @(
        @{ N = 1; What = 'Выгрузка в файлы'; Cmd = @('/DumpConfigToFiles', ('"' + $d1 + '"'), '-Extension', $ext) },
        @{ N = 2; What = 'Загрузка из файлов'; Cmd = @('/LoadConfigFromFiles', ('"' + $d1 + '"'), '-Extension', $ext) },
        @{ N = 3; What = 'Обновление базы'; Cmd = @('/UpdateDBCfg', '-Extension', $ext) },
        @{ N = 4; What = 'Проверка модулей'; Cmd = @('/CheckModules', '-ThinClient', '-Server', '-ExternalConnection', '-Extension', $ext) },
        @{ N = 5; What = 'Сборка .cfe'; Cmd = @('/DumpCfg', ('"' + $cfe + '"'), '-Extension', $ext) },
        @{ N = 6; What = 'Загрузка .cfe'; Cmd = @('/LoadCfg', ('"' + $cfe + '"'), '-Extension', $ext) },
        @{ N = 7; What = 'Повторная выгрузка'; Cmd = @('/DumpConfigToFiles', ('"' + $d2 + '"'), '-Extension', $ext) }
    )
    Write-Host "Тестовая база: $($cfg.TestIb). Машина: $env:COMPUTERNAME"
    if (-not $Run) {
        foreach ($s in $steps) { Write-Host ("{0}. {1}: {2} DESIGNER {3} {4} /Out <лог> /DisableStartupDialogs" -f $s.N, $s.What, $cfg.OneCExe, $cfg.TestIb, ($s.Cmd -join ' ')) }
        Write-Host 'Это только показ. Для выполнения добавьте -Run (сначала — копия тестовой базы).'
        exit 0
    }
    foreach ($p in @($d1, $d2)) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force } }
    $rows = New-Object System.Collections.Generic.List[string]
    $rows.Add('# С7. Пакетный режим Конфигуратора — результат'); $rows.Add('')
    $rows.Add("- Дата: $(Get-Date -Format 'dd.MM.yyyy HH:mm'); машина: $env:COMPUTERNAME; платформа: $((Get-Item -LiteralPath $cfg.OneCExe).VersionInfo.FileVersion)"); $rows.Add('')
    $rows.Add('| № | Команда | Код | Итог | Лог |'); $rows.Add('|---|---|---|---|---|')
    $failed = 0
    foreach ($s in $steps) {
        $r = Invoke-Designer $cfg 'TestIb' $s.Cmd $dir
        $ok = ($r.Code -eq 0)
        if ($s.N -eq 4 -and ($r.Log -match '(?i)ошибка|error')) { $ok = $false }
        if (-not $ok) { $failed++ }
        $rows.Add("| $($s.N) | $($s.What) (``$($s.Cmd[0])``) | $($r.Code) | $(if ($ok) { 'да' } else { 'НЕТ' }) | $(Split-Path -Leaf $r.LogFile) |")
        Write-Host ("{0}. {1}: {2}" -f $s.N, $s.What, $(if ($ok) { 'да' } else { "НЕТ (код $($r.Code), лог $($r.LogFile))" }))
    }
    if ((Test-Path -LiteralPath $d1) -and (Test-Path -LiteralPath $d2)) {
        $diff = Compare-Dumps $d1 $d2
        $rows.Add(''); $rows.Add("Круг «выгрузил → загрузил → собрал → загрузил → выгрузил»: отличающихся файлов $($diff.Count) (без ConfigDumpInfo.xml).")
        $diff | Select-Object -First 30 | ForEach-Object { $rows.Add("- $_") }
        if ($diff.Count -gt 0) { $failed++ }
        Write-Host "Круг выгрузки: отличий $($diff.Count)"
    }
    $res = Join-Path $dir 'result.md'
    [System.IO.File]::WriteAllText($res, ($rows -join "`r`n") + "`r`n", $script:Utf8NoBom)
    Write-Host "Итог: $res"
    if ($failed -gt 0) { exit 1 } else { exit 0 }
}
catch { Write-Host "СБОЙ: $($_.Exception.Message)"; exit 2 }
