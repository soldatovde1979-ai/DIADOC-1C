"""R3: события подключаемого модуля (ПМ) вендора — где вызываются и какие параметры передают.
Запуск: python3 tools/research/pm_events.py <каталог дистрибутива> [отчёт.md]
"""
import os, re, sys
from collections import defaultdict
FUNC = re.compile(r'^(?:Асинх\s+)?(?:Функция|Процедура)\s+([\wА-Яа-яЁё]+)\s*\(', re.I | re.M)
CALL = re.compile(r'(?:ПодключаемыйМодуль_|\.)?ОбработатьСобытие(?:ПередИМ|ПослеИМ)?\(\s*"([^"]+)"\s*(?:,\s*([\wА-Яа-яЁё]+))?')

def main(root, out=None):
    ev = defaultdict(lambda: {'where': set(), 'keys': set()})
    for d, _, fs in os.walk(root):
        for f in fs:
            if not f.endswith('.bsl'): continue
            p = os.path.join(d, f); t = open(p, encoding='utf-8-sig').read()
            heads = [(m.start(), m.group(1)) for m in FUNC.finditer(t)]
            for m in CALL.finditer(t):
                fstart, fname = max([h for h in heads if h[0] <= m.start()] or [(0, '(модуль)')])
                nxt = min([h[0] for h in heads if h[0] > m.start()] or [len(t)])
                body = t[fstart:nxt]
                e = ev[m.group(1)]
                e['where'].add(f"{os.path.relpath(p, root).split('/')[1]}.{fname}")
                var = m.group(2)
                if var:
                    for k in re.findall(re.escape(var) + r'\.Вставить\(\s*"([^"]+)"', body): e['keys'].add(k)
                    mm = re.search(re.escape(var) + r'\s*=\s*Новый\s+Структура\(\s*"([^"]+)"', body)
                    if mm: e['keys'].update(x.strip() for x in mm.group(1).split(','))
    L = ['# R3. События подключаемого модуля (ПМ): где вызываются и что получают', '',
         '> Версия: 1.0 · 07.10.2026 · Генератор: `python3 tools/research/pm_events.py SRC/TypeDiadok docs/research/R3-sobytiya-pm.md`.',
         '> Параметры собраны из кода вызова (`Параметры.Вставить(...)`, `Новый Структура(...)`). Если параметры формируются в другой функции — колонка пустая, смотреть код. Это выписка для сценария ТЗ-0 С9; документацию вендора она не заменяет.', '',
         f'Событий: **{len(ev)}**.', '', '| Событие | Где вызывается (обработка.функция) | Параметры, которые видно в коде вызова |', '|---|---|---|']
    for k in sorted(ev):
        L.append(f"| `{k}` | {'<br>'.join(sorted(ev[k]['where']))} | {', '.join(sorted(ev[k]['keys'])) or '—'} |")
    if out: open(out, 'w', encoding='utf-8').write('\n'.join(L) + '\n')
    print(len(ev))
if __name__ == '__main__':
    main(*sys.argv[1:])
