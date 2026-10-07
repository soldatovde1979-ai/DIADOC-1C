<#
.SYNOPSIS
  ТЗ-5. Автоматические проверки переноса наших правок в код вендора (Б1–Б5).
  Версия: 1.1 · 07.10.2026

.DESCRIPTION
  Б1  Метки ШХ <ID> в коде вендора ↔ таблица 3 реестра.
  Б2  Файлы форм (Form.xml) не отличаются от вендора; опорные элементы существуют.
  Б3  Сигнатурный контроль: вызовы функций вендора, куда мы добавили параметр, но вызов его не передаёт.
  Б4  Новое и изменённое у вендора в критичных модулях (только при -PrevVendorDir). Информация, не нарушение.
  Б5  Мёртвая дельта: наш помеченный код совпадает с кодом вендора. Предупреждение, не нарушение.

  Коды возврата: 0 — нарушений нет; 1 — есть нарушения; 2 — сбой самого скрипта.
  Запуск (Windows PowerShell 5.1+):
    powershell -NoProfile -File tools\checks\invariants.ps1 -VendorDir <выгрузка вендора> -WorkDir <наша выгрузка>
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $VendorDir,
    [Parameter(Mandatory = $true)] [string] $WorkDir,
    [string] $Registry = '',
    [string] $AnchorsFile = '',
    [string] $PrevVendorDir = '',
    [string] $Out = '',
    [string[]] $Checks = @('B1', 'B2', 'B3', 'B4', 'B5'),
    [string[]] $CriticalModules = @('КонтурДиадокГенерацияXML', 'КонтурДиадокЯдро', 'КонтурДиадокХранениеДанных')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
# Через powershell -File список «B1,B3» приходит одной строкой — разбираем сами.
$Checks = @($Checks | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$CriticalModules = @($CriticalModules | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

$Utf8 = New-Object System.Text.UTF8Encoding($false)
$RxOpt = [System.Text.RegularExpressions.RegexOptions]
$FuncRx = New-Object System.Text.RegularExpressions.Regex('^[ \t]*(?:Асинх[ \t]+)?(?:Функция|Процедура)[ \t]+([\wА-Яа-яЁё]+)[ \t]*\(', ($RxOpt::Multiline -bor $RxOpt::IgnoreCase))
$MarkRx = New-Object System.Text.RegularExpressions.Regex('шх', $RxOpt::IgnoreCase)
$IdRx = New-Object System.Text.RegularExpressions.Regex('//[^\r\n]*?ШХ[ \t]+(\d{2}-\d{2})', $RxOpt::IgnoreCase)

function Read-Text([string] $Path) { return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) }
function Get-RelPath([string] $Root, [string] $Full) {
    $r = (Resolve-Path -LiteralPath $Root).ProviderPath.TrimEnd('\', '/')
    return $Full.Substring($r.Length + 1).Replace('\', '/')
}
function Get-BslFiles([string] $Root) {
    $h = @{}
    foreach ($f in Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.bsl') { $h[(Get-RelPath $Root $f.FullName)] = $f.FullName }
    return $h
}

# Разбор списка аргументов: $Text начинается сразу после '('. Возвращает массив строк-аргументов или $null.
function Split-Args([string] $Text, [int] $Start) {
    $depth = 0; $inq = $false; $cur = New-Object System.Text.StringBuilder; $res = New-Object System.Collections.Generic.List[string]
    $max = [Math]::Min($Text.Length, $Start + 4000)
    for ($i = $Start; $i -lt $max; $i++) {
        $c = $Text[$i]
        if ($c -eq '"') { $inq = -not $inq }
        elseif (-not $inq) {
            if ($c -eq '/' -and ($i + 1) -lt $max -and $Text[$i + 1] -eq '/') {
                while ($i -lt $max -and $Text[$i] -ne "`n") { $i++ }; continue
            }
            if ($c -eq '(' -or $c -eq '[') { $depth++ }
            elseif ($c -eq ')' -or $c -eq ']') {
                if ($depth -eq 0) { $res.Add($cur.ToString().Trim()); return , $res.ToArray() }
                $depth--
            }
            elseif ($c -eq ',' -and $depth -eq 0) { $res.Add($cur.ToString().Trim()); [void]$cur.Clear(); continue }
        }
        [void]$cur.Append($c)
    }
    return $null
}

function Get-Signatures([string] $Text) {
    $h = @{}
    foreach ($m in $FuncRx.Matches($Text)) {
        $a = Split-Args $Text ($m.Index + $m.Length)
        if ($null -eq $a) { continue }
        $names = @()
        foreach ($x in $a) { if ($x -ne '') { $names += (($x -replace '^(?i)Знач\s+', '') -split '=')[0].Trim() } }
        $h[$m.Groups[1].Value] = $names
    }
    return $h
}

function Get-FunctionBodies([string] $Text) {
    $h = @{}; $ms = $FuncRx.Matches($Text)
    for ($k = 0; $k -lt $ms.Count; $k++) {
        $end = if ($k + 1 -lt $ms.Count) { $ms[$k + 1].Index } else { $Text.Length }
        $h[$ms[$k].Groups[1].Value] = $Text.Substring($ms[$k].Index, $end - $ms[$k].Index)
    }
    return $h
}

function Test-InComment([string] $Text, [int] $Pos) {
    $ls = $Text.LastIndexOf("`n", [Math]::Max($Pos - 1, 0)) + 1
    $seg = $Text.Substring($ls, $Pos - $ls)
    $inq = $false
    for ($i = 0; $i -lt $seg.Length - 1; $i++) {
        if ($seg[$i] -eq '"') { $inq = -not $inq }
        elseif (-not $inq -and $seg[$i] -eq '/' -and $seg[$i + 1] -eq '/') { return $true }
    }
    return $false
}
function Get-LineNo([string] $Text, [int] $Pos) { return ([regex]::Matches($Text.Substring(0, $Pos), "`n")).Count + 1 }

$violations = New-Object System.Collections.Generic.List[object]
$warnings = New-Object System.Collections.Generic.List[object]
$info = New-Object System.Collections.Generic.List[string]
function Add-V([string] $Check, [string] $Where, [string] $What) { $violations.Add([pscustomobject]@{ Check = $Check; Where = $Where; What = $What }) }
function Add-W([string] $Check, [string] $Where, [string] $What) { $warnings.Add([pscustomobject]@{ Check = $Check; Where = $Where; What = $What }) }

try {
    foreach ($d in @($VendorDir, $WorkDir)) { if (-not (Test-Path -LiteralPath $d -PathType Container)) { throw "Нет каталога: $d" } }
    $V = Get-BslFiles $VendorDir
    $W = Get-BslFiles $WorkDir
    $vendorFilesInWork = @($W.Keys | Where-Object { $V.ContainsKey($_) } | Sort-Object)
    $info.Add("Файлов .bsl: вендор $($V.Count), наша версия $($W.Count), общих $($vendorFilesInWork.Count).")
    $texts = @{}
    foreach ($k in $W.Keys) { $texts[$k] = Read-Text $W[$k] }

    # ---------- Б1 ----------
    if ($Checks -contains 'B1') {
        $reg = @{}
        if ($Registry -ne '') {
            if (-not (Test-Path -LiteralPath $Registry)) { throw "Нет файла реестра: $Registry" }
            $inT3 = $false
            foreach ($line in [System.IO.File]::ReadAllLines($Registry, [System.Text.Encoding]::UTF8)) {
                if ($line -match '^##\s+Таблица 3') { $inT3 = $true; continue }
                if ($inT3 -and $line -match '^##\s') { $inT3 = $false }
                if ($inT3 -and $line -match '^\|\s*(\d{2}-\d{2})\s*\|\s*([^|]+?)\s*\|') { $reg[$Matches[1]] = $Matches[2].Trim(' ', '`') }
            }
        }
        $codeIds = @{}
        foreach ($rel in $vendorFilesInWork) {
            $t = $texts[$rel]; $ln = 0
            foreach ($line in ($t -split "`n")) {
                $ln++
                if (-not $MarkRx.IsMatch($line)) { continue }
                $m = $IdRx.Match($line)
                if ($m.Success) {
                    $id = $m.Groups[1].Value
                    if (-not $codeIds.ContainsKey($id)) { $codeIds[$id] = New-Object System.Collections.Generic.HashSet[string] }
                    [void]$codeIds[$id].Add($rel)
                }
                elseif ($line -match '//') { Add-V 'Б1' "${rel}:$ln" 'Маркер ШХ без ID (ожидается // ШХ <NN-NN>)' }
            }
        }
        foreach ($id in ($codeIds.Keys | Sort-Object)) {
            if (-not $reg.ContainsKey($id)) { Add-V 'Б1' (($codeIds[$id] | Select-Object -First 1)) "Метка $id есть в коде, нет в таблице 3 реестра" ; continue }
            $want = $reg[$id]
            $ok = $false; foreach ($f in $codeIds[$id]) { if ($f -like "*$want*") { $ok = $true } }
            if (-not $ok) { Add-V 'Б1' (($codeIds[$id] | Select-Object -First 1)) "Метка $id не в том файле: по реестру «$want»" }
        }
        foreach ($id in ($reg.Keys | Sort-Object)) { if (-not $codeIds.ContainsKey($id)) { Add-V 'Б1' $reg[$id] "Метка $id есть в реестре, в коде не найдена (потеряна?)" } }
        $info.Add("Б1: меток с ID в коде — $($codeIds.Count), строк в таблице 3 — $($reg.Count).")
    }

    # ---------- Б2 ----------
    if ($Checks -contains 'B2') {
        $forms = 0; $diff = 0
        foreach ($f in Get-ChildItem -LiteralPath $WorkDir -Recurse -File -Filter 'Form.xml') {
            $rel = Get-RelPath $WorkDir $f.FullName
            $vf = Join-Path $VendorDir $rel
            if (-not (Test-Path -LiteralPath $vf)) { continue }
            $forms++
            $a = (Read-Text $vf) -replace "`r", ''
            $b = (Read-Text $f.FullName) -replace "`r", ''
            if ($a -ne $b) { $diff++; Add-V 'Б2' $rel 'Файл формы отличается от вендора (наши элементы должны создаваться кодом)' }
        }
        $info.Add("Б2: форм сравнено $forms, отличаются $diff.")
        if ($AnchorsFile -ne '') {
            foreach ($line in [System.IO.File]::ReadAllLines($AnchorsFile, [System.Text.Encoding]::UTF8)) {
                if ($line.Trim() -eq '' -or $line.TrimStart().StartsWith('#')) { continue }
                $p = $line.Split(';')
                $vf = Join-Path $VendorDir $p[0].Trim()
                if (-not (Test-Path -LiteralPath $vf)) { Add-V 'Б2' $p[0] 'Форма из списка опорных элементов не найдена у вендора'; continue }
                if (-not ((Read-Text $vf).Contains('name="' + $p[1].Trim() + '"'))) { Add-V 'Б2' $p[0] "Опорный элемент «$($p[1].Trim())» не найден в форме вендора" }
            }
        }
    }

    # ---------- Б3 ----------
    if ($Checks -contains 'B3') {
        $changed = New-Object System.Collections.Generic.List[object]
        foreach ($rel in $vendorFilesInWork) {
            $sv = Get-Signatures (Read-Text $V[$rel]); $sw = Get-Signatures $texts[$rel]
            foreach ($name in $sw.Keys) {
                if (-not $sv.ContainsKey($name)) { continue }
                $old = @($sv[$name]); $new = @($sw[$name])
                if ($new.Count -gt $old.Count -and (($old.Count -eq 0) -or (($new[0..($old.Count - 1)] -join '|') -eq ($old -join '|')))) {
                    $changed.Add([pscustomobject]@{ File = $rel; Name = $name; Need = $old.Count + 1; Added = ($new[$old.Count..($new.Count - 1)] -join ', ') })
                }
            }
        }
        $calls = 0
        foreach ($c in $changed) {
            $rx = New-Object System.Text.RegularExpressions.Regex('(?<![\wА-Яа-яЁё])' + [regex]::Escape($c.Name) + '\s*\(')
            foreach ($rel in $W.Keys) {
                $t = $texts[$rel]
                foreach ($m in $rx.Matches($t)) {
                    $ls = $t.LastIndexOf("`n", [Math]::Max($m.Index - 1, 0)) + 1
                    if ($FuncRx.IsMatch($t.Substring($ls, $m.Index + $m.Length - $ls))) { continue }
                    if (Test-InComment $t $m.Index) { continue }
                    $a = Split-Args $t ($m.Index + $m.Length)
                    if ($null -eq $a) { continue }
                    $calls++
                    $last = 0; for ($i = 0; $i -lt $a.Count; $i++) { if ($a[$i] -ne '') { $last = $i + 1 } }
                    if ($last -lt $c.Need) { Add-V 'Б3' "${rel}:$(Get-LineNo $t $m.Index)" "Вызов $($c.Name) без нашего параметра «$($c.Added)» (передано $last)" }
                }
            }
        }
        $info.Add("Б3: функций с добавленными параметрами — $($changed.Count), их вызовов — $calls.")
    }

    # ---------- Б4 ----------
    if ($Checks -contains 'B4') {
        if ($PrevVendorDir -eq '') { $info.Add('Б4: пропущено (не задан -PrevVendorDir).') }
        else {
            $P = Get-BslFiles $PrevVendorDir; $n = 0
            foreach ($rel in ($V.Keys | Sort-Object)) {
                $isCrit = $false; foreach ($cm in $CriticalModules) { if ($rel -like "*$cm/*") { $isCrit = $true } }
                if (-not $isCrit) { continue }
                $bn = Get-FunctionBodies (Read-Text $V[$rel])
                $bo = if ($P.ContainsKey($rel)) { Get-FunctionBodies (Read-Text $P[$rel]) } else { @{} }
                foreach ($name in ($bn.Keys | Sort-Object)) {
                    if (-not $bo.ContainsKey($name)) { Add-W 'Б4' $rel "Новая функция вендора: $name"; $n++ }
                    elseif (($bo[$name] -replace '\s', '') -ne ($bn[$name] -replace '\s', '')) { Add-W 'Б4' $rel "Изменена вендором: $name"; $n++ }
                }
            }
            $info.Add("Б4: новых/изменённых функций в критичных модулях — $n (просмотреть обязательно).")
        }
    }

    # ---------- Б5 ----------
    if ($Checks -contains 'B5') {
        $n = 0
        foreach ($rel in $vendorFilesInWork) {
            $vt = ((Read-Text $V[$rel]) -replace "`r", '')
            $vset = New-Object System.Collections.Generic.HashSet[string]
            foreach ($l in ($vt -split "`n")) { [void]$vset.Add($l.Trim()) }
            $ln = 0
            foreach ($line in ($texts[$rel] -split "`n")) {
                $ln++
                $m = $IdRx.Match($line)
                if (-not $m.Success) { continue }
                $code = $line.Substring(0, $line.IndexOf('//')).Trim()
                if ($code -ne '' -and $vset.Contains($code)) { Add-W 'Б5' "${rel}:$ln" "Метка $($m.Groups[1].Value): строка совпадает с кодом вендора — возможно, правка больше не нужна"; $n++ }
            }
        }
        $info.Add("Б5: кандидатов в мёртвую дельту — $n.")
    }

    # ---------- отчёт ----------
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# Отчёт проверок (ТЗ-5)'); [void]$sb.AppendLine()
    [void]$sb.AppendLine("- Дата: $(Get-Date -Format 'dd.MM.yyyy HH:mm')"); [void]$sb.AppendLine("- Вендор: ``$VendorDir``; наша версия: ``$WorkDir``")
    foreach ($i in $info) { [void]$sb.AppendLine("- $i") }
    [void]$sb.AppendLine("- **Нарушений: $($violations.Count)**, предупреждений: $($warnings.Count)"); [void]$sb.AppendLine()
    foreach ($pair in @(@('Нарушения', $violations), @('Предупреждения и информация для просмотра', $warnings))) {
        [void]$sb.AppendLine("## $($pair[0])"); [void]$sb.AppendLine()
        if ($pair[1].Count -eq 0) { [void]$sb.AppendLine('Нет.'); [void]$sb.AppendLine(); continue }
        [void]$sb.AppendLine('| Проверка | Где | Что |'); [void]$sb.AppendLine('|---|---|---|')
        foreach ($v in $pair[1]) { [void]$sb.AppendLine("| $($v.Check) | $($v.Where) | $($v.What) |") }
        [void]$sb.AppendLine()
    }
    if ($Out -ne '') {
        $dir = Split-Path -Parent $Out; if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
        [System.IO.File]::WriteAllText($Out, $sb.ToString(), $Utf8)
    }
    foreach ($i in $info) { Write-Host $i }
    Write-Host ("Нарушений: {0}; предупреждений: {1}" -f $violations.Count, $warnings.Count)
    if ($violations.Count -gt 0) { exit 1 } else { exit 0 }
}
catch {
    Write-Host "СБОЙ ПРОВЕРОК: $($_.Exception.Message)"
    exit 2
}
