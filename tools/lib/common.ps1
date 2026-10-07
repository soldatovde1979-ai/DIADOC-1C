<#
  Общие функции скриптов обновления Диадок (ТЗ-2, ТЗ-6). Подключается через точку: . "$PSScriptRoot\lib\common.ps1"
  Версия: 1.1 · 07.10.2026 · Windows PowerShell 5.1+
#>
$ErrorActionPreference = 'Stop'
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
# Пути с кириллицей: git не экранирует их (core.quotepath=false), а PowerShell читает вывод git как UTF-8, а не OEM-866.
$env:GIT_CONFIG_COUNT = '1'; $env:GIT_CONFIG_KEY_0 = 'core.quotepath'; $env:GIT_CONFIG_VALUE_0 = 'false'
try { [Console]::OutputEncoding = $script:Utf8NoBom } catch { }
$OutputEncoding = $script:Utf8NoBom

function Get-RepoRoot { return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath }

function Import-UpdateConfig([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Нет файла настроек: $Path (образец — tools\update.config.example.psd1)" }
    $cfg = Import-PowerShellDataFile -LiteralPath $Path
    foreach ($k in @('OneCExe', 'ExtensionName', 'SourceDir', 'MainBranch', 'VendorBranch', 'ServiceIb', 'TestIb')) {
        if (-not $cfg.ContainsKey($k) -or [string]::IsNullOrWhiteSpace([string]$cfg[$k])) { throw "В настройках не задан параметр $k" }
    }
    return $cfg
}

# Строка подключения к базе: '/F "D:\Base"' или '/S "server\base"' — задаётся в настройках как есть.
function Get-IbArgs([hashtable] $Cfg, [string] $IbKey) {
    $a = @()
    $a += ([string]$Cfg[$IbKey])
    if ($Cfg.ContainsKey('IbUser') -and $Cfg['IbUser']) { $a += ('/N "' + $Cfg['IbUser'] + '"') }
    if ($env:DIADOC_IB_PASSWORD) { $a += ('/P "' + $env:DIADOC_IB_PASSWORD + '"') }
    return $a
}

# Запуск Конфигуратора в пакетном режиме. Возвращает @{ Code; Log }.
function Invoke-Designer([hashtable] $Cfg, [string] $IbKey, [string[]] $Command, [string] $LogDir) {
    if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    $log = Join-Path $LogDir ('designer-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.log')
    $argList = @('DESIGNER') + (Get-IbArgs $Cfg $IbKey) + $Command + @('/Out', ('"' + $log + '"'), '/DisableStartupDialogs')
    $p = Start-Process -FilePath $Cfg.OneCExe -ArgumentList $argList -Wait -PassThru -NoNewWindow
    $text = if (Test-Path -LiteralPath $log) { [System.IO.File]::ReadAllText($log) } else { '' }
    return @{ Code = $p.ExitCode; Log = $text; LogFile = $log }
}

# Запуск в режиме Предприятия (для обработки формирования эталонов).
function Invoke-Enterprise([hashtable] $Cfg, [string] $IbKey, [string] $Epf, [string] $Param, [string] $LogDir) {
    if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    $log = Join-Path $LogDir ('enterprise-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.log')
    $argList = @('ENTERPRISE') + (Get-IbArgs $Cfg $IbKey) + @('/Execute', ('"' + $Epf + '"'), '/C', ('"' + $Param + '"'), '/Out', ('"' + $log + '"'), '/DisableStartupDialogs', '/DisableStartupMessages')
    $p = Start-Process -FilePath $Cfg.OneCExe -ArgumentList $argList -Wait -PassThru -NoNewWindow
    return @{ Code = $p.ExitCode; LogFile = $log }
}

function Assert-DesignerOk($Result, [string] $What) {
    if ($Result.Code -ne 0) { throw "$What`: Конфигуратор вернул код $($Result.Code). Лог: $($Result.LogFile)`n$($Result.Log)" }
}

# Вызов git с проверкой кода возврата. Возвращает вывод строками.
function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)] [string[]] $GitArgs)
    $out = & git @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw ("git " + ($GitArgs -join ' ') + " завершился с кодом $LASTEXITCODE`n" + ($out -join "`n")) }
    return $out
}

# Сравнение двух выгрузок (без служебного ConfigDumpInfo.xml и без различий в концах строк).
function Compare-Dumps([string] $A, [string] $B) {
    $diff = New-Object System.Collections.Generic.List[string]
    $ha = @{}; $hb = @{}
    foreach ($f in Get-ChildItem -LiteralPath $A -Recurse -File) { $r = $f.FullName.Substring($A.TrimEnd('\', '/').Length + 1).Replace('\', '/'); if ($r -notlike '*ConfigDumpInfo.xml') { $ha[$r] = $f.FullName } }
    foreach ($f in Get-ChildItem -LiteralPath $B -Recurse -File) { $r = $f.FullName.Substring($B.TrimEnd('\', '/').Length + 1).Replace('\', '/'); if ($r -notlike '*ConfigDumpInfo.xml') { $hb[$r] = $f.FullName } }
    foreach ($k in $ha.Keys) {
        if (-not $hb.ContainsKey($k)) { $diff.Add("нет во втором: $k"); continue }
        $x = ([System.IO.File]::ReadAllText($ha[$k]) -replace "`r", ''); $y = ([System.IO.File]::ReadAllText($hb[$k]) -replace "`r", '')
        if ($x -ne $y) { $diff.Add("отличается: $k") }
    }
    foreach ($k in $hb.Keys) { if (-not $ha.ContainsKey($k)) { $diff.Add("нет в первом: $k") } }
    return , $diff.ToArray()
}
