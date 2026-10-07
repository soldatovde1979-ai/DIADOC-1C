<#
.SYNOPSIS
  ТЗ-2 А1. Загрузка расширения из файлов в тестовую базу и проверка модулей (компиляция).
  Версия: 1.0 · 07.10.2026 · Windows PowerShell 5.1+
  ⚠️ Перезаписывает расширение в ТЕСТОВОЙ базе (TestIb из настроек). Прод не трогает.
  Код возврата: 0 — ошибок нет; 1 — есть ошибки компиляции; 2 — сбой.
.EXAMPLE
  powershell -NoProfile -File tools\checks\compile.ps1 -Config tools\update.config.psd1
#>
param(
    [string] $Config = (Join-Path $PSScriptRoot '..\update.config.psd1'),
    [string] $SourceDir = '',
    [string] $LogDir = ''
)
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
try {
    $cfg = Import-UpdateConfig $Config
    $root = Get-RepoRoot
    if ($SourceDir -eq '') { $SourceDir = Join-Path $root $cfg.SourceDir }
    if ($LogDir -eq '') { $LogDir = Join-Path $root 'out\compile' }
    $ext = $cfg.ExtensionName
    Write-Host "Загрузка расширения $ext из $SourceDir в тестовую базу..."
    $r = Invoke-Designer $cfg 'TestIb' @('/LoadConfigFromFiles', ('"' + $SourceDir + '"'), '-Extension', $ext) $LogDir
    Assert-DesignerOk $r 'Загрузка из файлов'
    $r = Invoke-Designer $cfg 'TestIb' @('/UpdateDBCfg', '-Extension', $ext) $LogDir
    Assert-DesignerOk $r 'Обновление базы (расширение)'
    Write-Host 'Проверка модулей...'
    $r = Invoke-Designer $cfg 'TestIb' @('/CheckModules', '-ThinClient', '-Server', '-ExternalConnection', '-Extension', $ext) $LogDir
    $errors = @($r.Log -split "`n" | Where-Object { $_ -match '(?i)ошибка|error|\{.+\(\d+,\d+\)\}' })
    if ($r.Code -ne 0 -or $errors.Count -gt 0) {
        Write-Host "ОШИБКИ КОМПИЛЯЦИИ ($($errors.Count)). Лог: $($r.LogFile)"
        $errors | Select-Object -First 50 | ForEach-Object { Write-Host "  $_" }
        exit 1
    }
    Write-Host 'Компиляция: ошибок нет.'
    exit 0
}
catch { Write-Host "СБОЙ: $($_.Exception.Message)"; exit 2 }
