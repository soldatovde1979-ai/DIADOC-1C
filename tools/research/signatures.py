"""R2: функции вендора с изменённой сигнатурой и все их вызовы (прототип проверки ТЗ-5 Б3).
Запуск: python3 tools/research/signatures.py <каталог дистрибутива> <каталог нашей версии> [отчёт.md]
"""
import os, re, sys
from collections import defaultdict

FUNC = re.compile(r'^\s*(?:Асинх\s+)?(?:Функция|Процедура)\s+([\wА-Яа-яЁё]+)\s*\(', re.I | re.M)

def strip_comments(text):
    out = []
    for line in text.split('\n'):
        res, i, inq = [], 0, False
        while i < len(line):
            c = line[i]
            if c == '"':
                inq = not inq
            if not inq and line.startswith('//', i):
                break
            res.append(c); i += 1
        out.append(''.join(res))
    return '\n'.join(out)

def split_args(s):
    """s начинается сразу после '(' ; вернуть (список аргументов, длина до ')')."""
    depth, inq, cur, args, i = 0, False, [], [], 0
    while i < len(s):
        c = s[i]
        if c == '"':
            inq = not inq
        elif not inq:
            if c in '([':
                depth += 1
            elif c in ')]':
                if depth == 0:
                    args.append(''.join(cur).strip()); return args, i
                depth -= 1
            elif c == ',' and depth == 0:
                args.append(''.join(cur).strip()); cur = []; i += 1; continue
        cur.append(c); i += 1
    return None, None

def params_of(text):
    res = {}
    for m in FUNC.finditer(text):
        args, _ = split_args(text[m.end():])
        if args is None: continue
        names = [re.sub(r'^Знач\s+', '', a, flags=re.I).split('=')[0].strip() for a in args if a.strip()]
        res[m.group(1)] = names
    return res

def read_all(root):
    files = {}
    for d, _, fs in os.walk(root):
        for f in fs:
            if f.endswith('.bsl'):
                p = os.path.join(d, f)
                files[os.path.relpath(p, root)] = strip_comments(open(p, encoding='utf-8-sig').read())
    return files

def main(vendor, ours, out=None):
    V, O = read_all(vendor), read_all(ours)
    changed = []
    for rel, text in O.items():
        if rel not in V: continue
        pv, po = params_of(V[rel]), params_of(text)
        for name, plist in po.items():
            if name in pv and len(plist) > len(pv[name]) and plist[:len(pv[name])] == pv[name]:
                changed.append((rel, name, pv[name], plist))
    rows = []
    for rel, name, old, new in changed:
        need = len(old) + 1
        call = re.compile(r'(?<![\wА-Яа-яЁё])' + re.escape(name) + r'\s*\(')
        for frel, text in O.items():
            for m in call.finditer(text):
                line_start = text.rfind('\n', 0, m.start()) + 1
                if FUNC.match(text[line_start:m.end()]):
                    continue  # это объявление, не вызов
                args, _ = split_args(text[m.end():])
                if args is None: continue
                n = len([a for a in args]) if args != [''] else 0
                # последний переданный непустой аргумент
                last = max([i + 1 for i, a in enumerate(args) if a.strip()] or [0])
                ok = last >= need
                rows.append((name, ', '.join(new[len(old):]), frel, text.count('\n', 0, m.start()) + 1, last, ok))
    bad = [r for r in rows if not r[5]]
    L = ['# R2. Сигнатурный анализ: наш параметр в вызовах функций вендора', '',
         '> Версия: 1.0 · 07.10.2026 · Генератор: `python3 tools/research/signatures.py SRC/TypeDiadok SRC/ERPDiadok docs/research/R2-signatury.md`.',
         '> Прототип проверки ТЗ-5 (Б3). Комментарии в коде не учитываются.', '',
         '## Главное', '',
         f'- Функций вендора, в которые мы добавили параметры: **{len(changed)}**.',
         f'- Их вызовов в нашей версии: **{len(rows)}**, из них **без нашего параметра: {len(bad)}**.',
         '- «Без нашего параметра» не всегда ошибка: часть вызовов осознанно идёт без договора (общие настройки). Но каждое такое место — кандидат на проверку человеком: именно так будут выглядеть новые вызовы вендора после обновления.', '',
         '## Функции с добавленными параметрами', '',
         '| Файл | Функция | Добавлено | Было параметров |', '|---|---|---|---|']
    for rel, name, old, new in sorted(changed, key=lambda x: (x[0], x[1])):
        L.append(f'| {rel.split("/")[1]} | `{name}` | `{", ".join(new[len(old):])}` | {len(old)} |')
    L += ['', '## Вызовы без нашего параметра', '', '| Функция | Наш параметр | Файл | Строка | Передано аргументов |', '|---|---|---|---|---|']
    for r in sorted(bad, key=lambda r: (r[0], r[2], r[3])):
        L.append(f'| `{r[0]}` | `{r[1]}` | {r[2].split("/")[1]} | {r[3]} | {r[4]} |')
    L += ['', '## Вызовы с нашим параметром (для справки)', '', '| Функция | Файл | Строка |', '|---|---|---|']
    for r in sorted([r for r in rows if r[5]], key=lambda r: (r[0], r[2], r[3])):
        L.append(f'| `{r[0]}` | {r[2].split("/")[1]} | {r[3]} |')
    text = '\n'.join(L) + '\n'
    if out: open(out, 'w', encoding='utf-8').write(text)
    print(len(changed), len(rows), len(bad))

if __name__ == '__main__':
    main(*sys.argv[1:])
