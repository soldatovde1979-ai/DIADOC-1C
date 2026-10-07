import difflib, re, os, sys, json
ROOT=sys.argv[1]; E=os.path.join(ROOT,'SRC/ERPDiadok'); T=os.path.join(ROOT,'SRC/TypeDiadok')
FILES=[
 ('DataProcessors/КонтурДиадокВызовыПМ/Ext/ObjectModule.bsl','ВызовыПМ'),
 ('DataProcessors/КонтурДиадокИнтеграцияУТ11/Ext/ObjectModule.bsl','ИнтеграцияУТ11'),
 ('DataProcessors/КонтурДиадокСтандартУФ/Ext/ObjectModule.bsl','СтандартУФ'),
 ('DataProcessors/КонтурДиадокГенерацияXML/Ext/ObjectModule.bsl','ГенерацияXML'),
 ('DataProcessors/КонтурДиадокЯдро/Ext/ObjectModule.bsl','Ядро'),
 ('DataProcessors/КонтурДиадокХранениеДанных/Ext/ObjectModule.bsl','ХранениеДанных'),
 ('DataProcessors/КонтурЭДО/Ext/ObjectModule.bsl','КонтурЭДО'),
 ('DataProcessors/КонтурДиадокСтандартУФ_Модуль_ИнтеграцияУТ11/Ext/ObjectModule.bsl','СтандартУФ_ИнтеграцияУТ11'),
 ('DataProcessors/КонтурДиадокСтандартУФ_Модуль_ИнтеграцияУниверсальный/Ext/ObjectModule.bsl','СтандартУФ_ИнтеграцияУниверсальный'),
 ('DataProcessors/КонтурЭДО/Forms/ФормаУправляемая/Ext/Form/Module.bsl','ФормаУправляемая'),
 ('DataProcessors/КонтурЭДО/Forms/ФормаЭлементаСправочникаУправляемая/Ext/Form/Module.bsl','ФормаЭлементаСправочника'),
 ('DataProcessors/КонтурЭДО/Forms/НастройкаПечатныхФормУправляемая/Ext/Form/Module.bsl','НастройкаПечатныхФорм'),
 ('DataProcessors/КонтурЭДО/Forms/НастройкиУправляемая/Ext/Form/Module.bsl','НастройкиУправляемая'),
 ('DataProcessors/КонтурЭДО/Forms/ФормаПакетаУправляемая/Ext/Form/Module.bsl','ФормаПакета'),
]
def pos(short, func, txt=''):
    f=func or ''
    if '00-00020261' in txt and short in ('Ядро','ХранениеДанных') and not f.startswith('СписокДокументов_'): return 26
    fixed={'ВызовыПМ':4,'ИнтеграцияУТ11':5,'СтандартУФ':6,'ГенерацияXML':7,'КонтурЭДО':16,'ФормаУправляемая':17,
           'ФормаЭлементаСправочника':18,'НастройкаПечатныхФорм':19,'НастройкиУправляемая':20,'ФормаПакета':21,
           'СтандартУФ_ИнтеграцияУТ11':24,'СтандартУФ_ИнтеграцияУниверсальный':25}
    if short in fixed: return fixed[short]
    if short=='Ядро':
        if f.startswith('ПодключаемыйМодуль_СовместимыеПараметры'): return 9
        if f.startswith('Документы_ПослеОтправкиMessagePatchToPost'): return 26
        if f.startswith('ТиповойМодуль_СоздатьДокумент'): return 24
        if f.startswith('Контракт_'): return 10
        if f.startswith('ОбновлениеМодуля_'): return 11
        if re.match(r'(Пакеты_|Документы_ЗаполнитьДокументБезКонтента|ПодключаемыйМодуль_ПодготовитьЭлектронныйДокументПоВнешнейПечатнойФорме|Интеграция_ПодготовитьЭлектронныйДокумент|УПД970_|ОбщиеНастройки_ОбработанныеЗначенияПередЗаписью)',f): return 12
        if re.match(r'(НастройкиДокументов_|НастройкиПечатныхФорм_|ХранениеДанных_|Документы_ПараметрыОтправкиВидаДокумента)',f): return 8
        return None
    if short=='ХранениеДанных':
        if 'Гирфанов' in txt: return 2
        if f.startswith('СписокДокументов_'): return 15
        if f.startswith('Документы_ЗаписатьДанныеХранилища') or f.startswith('КонтурПлагины_') or f.startswith('Документы_КонтрактДанныхХранилища') or f.startswith('Документы_КонтрактПодписи') or 'ПрикрепленныеФайлы' in txt: return 14
        if re.match(r'(Настройки_|ТекстЗапроса_Настройки|НастройкиПечатныхФорм_|Справочники_.*НастроекКонтрагентов)',f): return 13
        return None
FUNC=re.compile(r'^\s*(?:Асинх\s+)?(Функция|Процедура)\s+([\wА-Яа-яЁё]+)\s*\(', re.I)
AUTH=re.compile(r'т1к\s+([А-ЯЁ][а-яё]?\.?[А-ЯЁ]?\.?\s*[А-ЯЁ][а-яё]+),?\s*(\d{4}-\d{2}-\d{2})')
rows=[]
for rel,short in FILES:
    a=open(os.path.join(T,rel),encoding='utf-8-sig').read().splitlines()
    b=open(os.path.join(E,rel),encoding='utf-8-sig').read().splitlines()
    # function owning each line in b
    owner=[None]*len(b); cur=None
    for i,l in enumerate(b):
        m=FUNC.match(l)
        if m: cur=m.group(2)
        owner[i]=cur
        if re.match(r'^\s*Конец(Функции|Процедуры)',l,re.I): pass
    sm=difflib.SequenceMatcher(None,a,b,autojunk=False)
    for tag,i1,i2,j1,j2 in sm.get_opcodes():
        if tag=='equal': continue
        added=b[j1:j2]; removed=a[i1:i2]
        ln=j1 if j1<len(b) else len(b)-1
        func=owner[max(ln,0)] if b else None
        # if hunk begins with function header itself
        for l in added:
            m=FUNC.match(l)
            if m: func=func or m.group(2); break
        txt='\n'.join(added+removed)
        au=AUTH.search(txt)
        rows.append(dict(file=short,line=j1+1,func=func,add=len(added),rem=len(removed),
            pos=pos(short,func,txt),author=(au.group(1) if au else ''),date=(au.group(2) if au else ''),
            newfunc=any(FUNC.match(l) for l in added), shx=('ШХ' in txt)))
json.dump(rows,open(sys.argv[2],'w',encoding='utf-8'),ensure_ascii=False,indent=0)
from collections import Counter
print(len(rows),'участков'); print(Counter(r['pos'] for r in rows))
print('без позиции:',[(r['file'],r['line'],r['func']) for r in rows if r['pos'] is None][:40])
print('без ШХ в тексте:',sum(1 for r in rows if not r['shx']))
