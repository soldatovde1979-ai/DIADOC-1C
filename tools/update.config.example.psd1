# Настройки tools\update.ps1 и скриптов проверок (ТЗ-6). Версия: 1.0 · 07.10.2026
# Скопируйте в tools\update.config.psd1 и заполните. Пароль сюда НЕ писать —
# только переменная окружения DIADOC_IB_PASSWORD (PowerShell: $env:DIADOC_IB_PASSWORD = '...').
@{
    # Платформа 1С
    OneCExe          = 'C:\Program Files\1cv8\8.3.24.1548\bin\1cv8.exe'
    PlatformVersion  = '8.3.24.1548'          # выгрузки vendor и основной ветки — только этой версией (ТЗ-0, Ф9)

    # Расширение и репозиторий
    ExtensionName    = 'КонтурДиадок'
    SourceDir        = 'SRC/КонтурДиадок'     # каталог выгрузки расширения в репозитории (ТЗ-1)
    MainBranch       = 'main'
    VendorBranch     = 'vendor'

    # Базы. Формат — как в командной строке 1С: '/F "D:\1C\База"' (файловая) или '/S "сервер\база"'
    ServiceIb        = '/F "D:\1C\Diadoc_Service"'   # пустая служебная база: сюда грузится новый .cfe вендора
    TestIb           = '/F "D:\1C\Diadoc_Test"'      # копия прода: компиляция и эталоны
    ProdCopyIb       = '/F "D:\1C\Diadoc_ProdCopy"'  # свежая копия прода для сверки (или задайте ProdCfe)
    ProdCfe          = ''                            # .cfe, выгруженный администратором из прода (если нет ProdCopyIb)
    IbUser           = 'Администратор'

    # Эталоны поведения (ТЗ-2)
    ReferenceEpf     = 'tools/checks/reference/ЭталоныXML.epf'

    # Пропустить проверки, требующие 1С (компиляция, эталоны) — только для отладки скрипта
    SkipOneCChecks   = $false
}
