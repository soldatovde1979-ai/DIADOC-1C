<#
.SYNOPSIS
  ТЗ-2 А2. Эталонные XML: сформировать по тестовым документам и сравнить с эталоном.
  Версия: 1.0 · 07.10.2026 · Windows PowerShell 5.1+

.DESCRIPTION
  1. (если не задан -SkipGenerate) запускает в ТЕСТОВОЙ базе обработку формирования эталонов
     (ReferenceEpf из настроек) с параметром запуска = каталог результата;
  2. маскирует меняющиеся значения (GUID, даты/время, номера пакетов) и сравнивает с tools\checks\reference\expected;
  3. с -Snapshot — сохраняет результат как новый эталон (только осознанно: при первом снятии или
     после разобранного изменения формата вендором, с записью в журнал).
  Код возврата: 0 — совпало; 1 — есть отличия; 2 — сбой.
#>
param(
    [string] $Config = (Join-Path $PSScriptRoot '..\update.config.psd1'),
    [string] $ActualDir = '',
    [string] $ExpectedDir = (Join-Path $PSScriptRoot 'reference\expected'),
    [switch] $SkipGenerate,
    [switch] $Snapshot
)
. (Join-Path $PSScriptRoot '..\lib\common.ps1')

function Get-Masked([string] $Text) {
    $t = $Text -replace "`r", ''
    $t = [regex]::Replace($t, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '***GUID***')
    $t = [regex]::Replace($t, '\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})?', '***ДАТАВРЕМЯ***')
    $t = [regex]::Replace($t, '(?<=ВремИнфПр=")[^"]*', '***')
    $t = [regex]::Replace($t, '(?<=ДатаИнфПр=")[^"]*', '***')
    $t = [regex]::Replace($t, '(?<=ИдФайл=")[^"]*', '***')
    return $t
}

try {
    $root = Get-RepoRoot
    if ($ActualDir -eq '') { $ActualDir = Join-Path $root 'out\reference\actual' }
    if (-not $SkipGenerate) {
        $cfg = Import-UpdateConfig $Config
        $epf = Join-Path $root $cfg.ReferenceEpf
        if (-not (Test-Path -LiteralPath $epf)) { throw "Нет обработки формирования эталонов: $epf (ТЗ-2 §2.3)" }
        if (Test-Path -LiteralPath $ActualDir) { Remove-Item -LiteralPath $ActualDir -Recurse -Force }
        New-Item -ItemType Directory -Path $ActualDir -Force | Out-Null
        Write-Host 'Формирование эталонных XML в тестовой базе...'
        $r = Invoke-Enterprise $cfg 'TestIb' $epf $ActualDir (Join-Path $root 'out\reference')
        if ($r.Code -ne 0) { throw "Обработка формирования эталонов завершилась с кодом $($r.Code). Лог: $($r.LogFile)" }
    }
    if (-not (Test-Path -LiteralPath $ActualDir)) { throw "Нет каталога результата: $ActualDir" }
    if ($Snapshot) {
        if (Test-Path -LiteralPath $ExpectedDir) { Remove-Item -LiteralPath $ExpectedDir -Recurse -Force }
        Copy-Item -LiteralPath $ActualDir -Destination $ExpectedDir -Recurse
        Write-Host "Эталон сохранён: $ExpectedDir. Закоммитьте его и запишите причину в журнал."
        exit 0
    }
    if (-not (Test-Path -LiteralPath $ExpectedDir)) { throw "Нет эталона: $ExpectedDir. Сначала снимите его с -Snapshot на текущем коде (ТЗ-2)." }
    $exp = @{}; $act = @{}
    foreach ($f in Get-ChildItem -LiteralPath $ExpectedDir -Recurse -File) { $exp[$f.FullName.Substring($ExpectedDir.TrimEnd('\', '/').Length + 1).Replace('\', '/')] = $f.FullName }
    foreach ($f in Get-ChildItem -LiteralPath $ActualDir -Recurse -File) { $act[$f.FullName.Substring($ActualDir.TrimEnd('\', '/').Length + 1).Replace('\', '/')] = $f.FullName }
    $bad = 0
    foreach ($k in ($exp.Keys | Sort-Object)) {
        if (-not $act.ContainsKey($k)) { Write-Host "  НЕТ    $k"; $bad++; continue }
        $a = Get-Masked ([System.IO.File]::ReadAllText($exp[$k])); $b = Get-Masked ([System.IO.File]::ReadAllText($act[$k]))
        if ($a -ne $b) {
            $bad++; Write-Host "  ОТЛИЧ  $k"
            $la = $a -split "`n"; $lb = $b -split "`n"
            for ($i = 0; $i -lt [Math]::Max($la.Count, $lb.Count); $i++) {
                $x = if ($i -lt $la.Count) { $la[$i] } else { '<нет>' }; $y = if ($i -lt $lb.Count) { $lb[$i] } else { '<нет>' }
                if ($x -ne $y) { Write-Host "         строка $($i + 1): было «$($x.Trim())» стало «$($y.Trim())»"; break }
            }
        }
        else { Write-Host "  ОК     $k" }
    }
    foreach ($k in ($act.Keys | Sort-Object)) { if (-not $exp.ContainsKey($k)) { Write-Host "  ЛИШНИЙ $k"; $bad++ } }
    if ($bad -gt 0) { Write-Host "Эталоны: отличий — $bad"; exit 1 }
    Write-Host 'Эталоны: всё совпало.'; exit 0
}
catch { Write-Host "СБОЙ: $($_.Exception.Message)"; exit 2 }
