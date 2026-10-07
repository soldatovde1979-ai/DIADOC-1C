<#
.SYNOPSIS
  ТЗ-5 Б6. Проверка чувствительности invariants.ps1: на чистом примере — 0 нарушений, каждая порча — нарушение.
  Версия: 1.0 · 07.10.2026
  Запуск: powershell -NoProfile -File tools\checks\selftest.ps1
  Код возврата: 0 — все проверки чувствительны; 1 — хотя бы одна «слепая»; 2 — сбой.
#>
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Utf8Bom = New-Object System.Text.UTF8Encoding($true)
$Inv = Join-Path $PSScriptRoot 'invariants.ps1'
$Ps = (Get-Process -Id $PID).Path

function Write-File([string] $Path, [string] $Text) {
    $d = Split-Path -Parent $Path; if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Text, $Utf8Bom)
}

function New-Fixture([string] $Root) {
    $mod = 'DataProcessors/Обр/Ext/ObjectModule.bsl'
    $frm = 'DataProcessors/Обр/Forms/Форма/Ext/Form.xml'
    Write-File (Join-Path $Root "vendor/$mod") @"
Функция Прочитать(Вид, Организация, Контрагент) Экспорт
	Возврат 1;
КонецФункции

Процедура Использовать()
	А = Прочитать(1, 2, 3);
	Б = 5;
КонецПроцедуры
"@
    Write-File (Join-Path $Root "work/$mod") @"
Функция Прочитать(Вид, Организация, Контрагент, Договор1С = Неопределено) Экспорт // ШХ 01-01
	Возврат 1;
КонецФункции

Процедура Использовать()
	А = Прочитать(1, 2, 3, Д); // ШХ 01-02
	Б = 5; // ШХ 01-03
КонецПроцедуры
"@
    $form = '<Form><Items><UsualGroup name="ГруппаКнопок"/></Items></Form>'
    Write-File (Join-Path $Root "vendor/$frm") $form
    Write-File (Join-Path $Root "work/$frm") $form
    Write-File (Join-Path $Root 'registry.md') @"
## Таблица 3. Метки

| ID | Файл | Функция |
|---|---|---|
| 01-01 | Обр/Ext/ObjectModule.bsl | Прочитать |
| 01-02 | Обр/Ext/ObjectModule.bsl | Использовать |
| 01-03 | Обр/Ext/ObjectModule.bsl | Использовать |

## Сводка
"@
    Write-File (Join-Path $Root 'anchors.csv') "DataProcessors/Обр/Forms/Форма/Ext/Form.xml;ГруппаКнопок"
    return @{ Mod = (Join-Path $Root "work/$mod"); Frm = (Join-Path $Root "work/$frm") }
}

function Invoke-Inv([string] $Root) {
    $o = Join-Path $Root 'out.md'
    & $Ps -NoProfile -File $Inv -VendorDir (Join-Path $Root 'vendor') -WorkDir (Join-Path $Root 'work') -Registry (Join-Path $Root 'registry.md') -AnchorsFile (Join-Path $Root 'anchors.csv') -Out $o | Out-Null
    return @{ Code = $LASTEXITCODE; Report = [System.IO.File]::ReadAllText($o) }
}

$failed = 0
function Assert([bool] $Cond, [string] $Name) {
    if ($Cond) { Write-Host "  ОК   $Name" } else { Write-Host "  СЛЕП $Name"; $script:failed++ }
}

try {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('inv-selftest-' + [guid]::NewGuid().ToString('N'))
    Write-Host 'Чистый пример:'
    $f = New-Fixture $tmp; $r = Invoke-Inv $tmp
    Assert ($r.Code -eq 0) 'нарушений нет (код 0)'
    Assert ($r.Report -match '\| Б5 \|') 'Б5 видит строку, совпадающую с вендором (01-03)'

    $cases = @(
        @{ Name = 'Б1: удалена метка 01-02';           Check = 'Б1'; Do = { param($f) $t = [IO.File]::ReadAllText($f.Mod); [IO.File]::WriteAllText($f.Mod, $t.Replace('Д); // ШХ 01-02', 'Д);'), $Utf8Bom) } },
        @{ Name = 'Б1: маркер ШХ без ID';               Check = 'Б1'; Do = { param($f) $t = [IO.File]::ReadAllText($f.Mod); [IO.File]::WriteAllText($f.Mod, $t.Replace('// ШХ 01-03', '// + ШХ'), $Utf8Bom) } },
        @{ Name = 'Б3: из вызова убран наш параметр';  Check = 'Б3'; Do = { param($f) $t = [IO.File]::ReadAllText($f.Mod); [IO.File]::WriteAllText($f.Mod, $t.Replace('Прочитать(1, 2, 3, Д)', 'Прочитать(1, 2, 3)'), $Utf8Bom) } },
        @{ Name = 'Б2: в форму добавлен элемент';       Check = 'Б2'; Do = { param($f) $t = [IO.File]::ReadAllText($f.Frm); [IO.File]::WriteAllText($f.Frm, $t.Replace('</Items>', '<CheckBoxField name="шхНовый"/></Items>'), $Utf8Bom) } }
    )
    foreach ($c in $cases) {
        Write-Host "Порча — $($c.Name):"
        Remove-Item -LiteralPath $tmp -Recurse -Force
        $f = New-Fixture $tmp; & $c.Do $f; $r = Invoke-Inv $tmp
        Assert (($r.Code -eq 1) -and ($r.Report -match ('\| ' + $c.Check + ' \|'))) "обнаружено проверкой $($c.Check) (код 1)"
    }
    Write-Host 'Сбой (нет каталога):'
    & $Ps -NoProfile -File $Inv -VendorDir (Join-Path $tmp 'нет') -WorkDir (Join-Path $tmp 'work') | Out-Null
    Assert ($LASTEXITCODE -eq 2) 'код 2'
    Remove-Item -LiteralPath $tmp -Recurse -Force
    if ($failed -gt 0) { Write-Host "ИТОГ: слепых проверок — $failed"; exit 1 }
    Write-Host 'ИТОГ: все проверки чувствительны'; exit 0
}
catch { Write-Host "СБОЙ САМОПРОВЕРКИ: $($_.Exception.Message)"; exit 2 }
