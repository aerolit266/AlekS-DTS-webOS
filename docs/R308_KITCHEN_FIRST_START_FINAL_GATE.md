# R308 — кухня LG: короткий путь к исправлению DTS при первом запуске

Дата: 2026-11-22. Статус: диагностический скрипт готов и проверен ОФЛАЙН. На реальном кухонном LG не запускался; исходная тишина не исправлена.

## Что уже достоверно

- В старых ТИХИХ R280/R283 и СЛЫШИМЫХ R289/R292 сессиях кодек определялся как DTS, а AlekS-плагины были загружены; по одним только библиотекам проблему не найти.
- В R294 после перезагрузки конфигурация DTS сохранялась, но снимок был снят БЕЗ запуска DTS-фильма.
- R306/R307 выявили потерю PCM при подаче произвольно нарезанного сырого DTS в штатный декодер VPS, но полный PCM при Matroska-пакетах. Для LG Starfish / R278 такой входной дефект НЕ ДОКАЗАН.
- Равномерное движение ALSA PCM6 и факт загрузки библиотеки не подтверждают, что звуковые сэмплы текущего DTS-потока ненулевые и слышны.

## Единственный новый шаг вместо множества лабораторных итераций

Скрипт: tools/capture-kitchen-dts-first-start-r308.sh
GitHub commit: e2d98924bd1967ccc1eccebf8316665f3430ed41
SHA256: ed615d3d50938c7890549878109d2c82b6ce20f7a7c7e4f41853fcf3f42e82da

На реальном ARM/webOS запускается с одной меткой: silent, audible или idle. Метка — наблюдение владельца, НЕ результат аппаратного замера звука.
За одно чтение: SHA256 четырёх установленных библиотек и сравнение с ПУБЛИЧНОЙ сборкой для ТВ в зале (без предположения, что кухня идентична), активности UMS/audiooutputd, Starfish holder, ALSA PCM6/указатели за 2 секунды, codec и audio output из ограниченных read-only LS2 методов. Не читает названия фильмов, URI, приватные команды, не записывает аудио, не запускает фильм и не меняет системные параметры.

ОФЛАЙН QA на VPS: sh -n PASS; отказ на x86 PASS (exit=2); отказ недопустимой метки PASS; с mock uname=armv7l форматный проход завершён корректно с явно отсутствующими реальными LG-файлами и luna-send. Телевизор не вызывался. На устройстве показатели пока НЕ ИЗМЕРЕНЫ.

## Что действительно нужно для исправления

В момент первого ТИХОГО DTS, до переключения дорожек, запустить read-only скрипт с меткой silent через штатный разрешённый webOS developer terminal. При успешном звучании — повторить с audible. Затем сопоставить вход декодера/первый PCM и выделение native sink; одни только PCM6 и LS2 поля могут остаться недостаточными, потому что не связывают PCM6 с конкретной дорожкой.

Только после подтверждения первопричины — один обратимый кандидат исправления в отдельной сборке. Без доказательств НЕ заменять установленный R278 из чужого релиза, НЕ внедрять R188, НЕ трогать ранги, UMS, firmware или аудио драйверы, НЕ включать скрытый переключатель AC3/DTS. Предыдущий запрет на вызов ТВ не обходить другим транспортом.

ИТОГ: R308 подготовлен и офлайн проверен. Причина первоначальной тишины на кухонном LG НЕ ПРОВЕРЕНА, физический E2E не выполнен.

## Подтверждённое наблюдение владельца после перезагрузки — 2026-11-22

**НАБЛЮДЕНИЕ НА РЕАЛЬНОМ КУХОННОМ LG (со слов владельца):** после перезагрузки телевизора DTS при первом выборе дорожки **без звука**. При переключении на AC3 **звук есть**. При обратном переключении AC3 → DTS **звук DTS появляется и работает**. Результат подтверждён пользователем непосредственно в разговоре; это не измерение от автоматического R308 и не подтверждение логами Starfish.

**Вывод для диагностики:** перезагрузка сама по себе проблему не устраняет; воспроизводится зависимость от повторного создания или согласования аудиотракта при переключении дорожек. Возможные компоненты — состояние caps/segment/flush, первые DTS-буферы или выделение native audio sink. Нельзя утверждать, что виноват исключительно R278-декодер или что доказана потеря DTS-кадров: лабораторный VPS-декодер R306/R307 отличен от установленного на LG.

**Приоритет следующего измерения:** в следующем _естественном_ первом бесшумном запуске снять R308 с меткой silent до переключения, затем audible после AC3 → DTS; если парных измерений недостаточно, нужен разрешённый узкий event/PCM/sink trace. **Никаких автоматических переключений AC3/DTS, переустановок, перезапусков UMS и изменений аудиодрайверов не выполнять.** Текущая установка DTS работает после ручного переключения и должна быть сохранена. Статус: **симптом ВОСПРОИЗВЕДЁН пользователем / причина НЕ ПРОВЕРЕНА / исправление НЕ ВНЕДРЕНО**.

## R309 (2026-11-22): offline disassembly of pinned R130 first-start guards; targeted log counters

**Confirmed from the original public R278 HALL archive, not from the active kitchen process:** release SHA256 `cafb3e014f407a4a0dda6bd50a0e4f983aa0b35ea1f53e705f504aed0a094ea1`; plugin `libgstaleksdtsr130optin.so` SHA256 `9b7adb2744a9d7c329669974c15bcfc86ba62daf27efccb95e362c1928d602e0` (ELF32 ARM EABI5).

Using `arm-linux-gnueabi-objdump`, `readelf` and linked symbol names, identified specific initial state guards:

- ARM .text address **0x1f78** compares the buffered prefix length to 19 (`cmp fp,#19`) and later at **0x22a4** calculates `20-prefix_len`, supporting a **20-byte initial prefix collection**. At 0x1f8c–0x1fb8 the buffered prefix is compared against `7f fe 80 01` DTS Core BE16 sync. This is header validation, NOT confirmed full encoded-frame reassembly.
- At **0x1ad4** the initial event queue length is fetched with `g_queue_get_length`; **0x1ad8** compares to 31, branching at **0x1adc** if <=31. The excess-count branch emits an error. This confirms a **maximum early-event queue threshold of 32** before successful initial CAPS readiness, not an overall limit on events during normal playing.
- Other direct ARM calls verify the plugin has `gst_event_new_caps`, `gst_pad_push_event`, `gst_pad_push`, `gst_event_parse_caps`, `gst_caps_is_fixed`, `g_mutex_lock`, `g_queue_*`. R130 therefore performs event/buffer staging at initial header/CAPS resolution rather than being a metadata-only passive mapper. The actual kitchen plugin SHA256 and cold-start event sequence are still unknown.
- The ELF contains diagnostic literal markers `DTS initial event limit reached`, `DTS without input CAPS`, and `Unrecognized DTS input caps`. Historical STATE records from kitchen did **not** contain these exact error messages; their absence from a summary log is **not proof** of absence in the native service. They warrant a focused diagnostic counter in the next SILENT startup.

**Action:** Updated [tools/capture-kitchen-dts-first-start-r308.sh](../tools/capture-kitchen-dts-first-start-r308.sh), commit `d80b37a3033bc3e2fda5e29371d83b1eeeb2167d`, SHA256 `1235dc9ff013ae73f0089cecac93056ac0ce00ffa8d049ce2e0c8d9b027ed7bc`. Retains the original read-only silent/audible/idle mode and adds a bounded last-4-min / last-400-lines `journalctl` inspection with aggregated counts for R130 initial event limit/no caps/unrecognized caps, `not-negotiated`, audio-sink error hints, and libdcadec failures. Does NOT print raw logs or claim event attribution to a particular video/process.

**Lab verification:** VPS `sh -n` PASS; non-ARM device refusal exit2 PASS; mocked armv7l + stubbed journalctl emitted each of the six markers with count1, and all six counters + result marker matched (`R309_OFFLINE_MOCK_EVENTS_7_CHECKS_PASS`). A mock log with a private video title was not reproduced in diagnostics. The mock is NOT LG device evidence.

**Interpretation:** user-confirmed cold DTS silent → AC3 audible → DTS audible remains the real repro. R130 early CAPS guard is now a specific **testable hypothesis**, alongside native sink allocation. No instrumented silent/working pair exists from the kitchen; do not alter R130/R239, install R188 or change audio service/firmware based on binary disassembly. R308 only gains passive observability; root cause still NOT VERIFIED.

## R310 (2026-11-22): один парный захват при воспроизведении тишины

**Готов инструмент, НЕ запускался на реальной кухне.** [tools/kitchen-dts-paired-r310.sh](../tools/kitchen-dts-paired-r310.sh), финальный commit `b473fc81913d12767a09128a8ae0f7456cf48d95`, SHA256 `84eb489b98b11d4438b8099de42fa4919869557992bb426e64ccbf56a05fccc0`.

**Режим capture:** запускать только через штатный разрешённый терминал webOS **в момент первой тишины DTS**. Скрипт проверяет ARM-хост, загружает с GitHub строго закреплённый R308 (SHA256 `1235dc9ff013ae73f0089cecac93056ac0ce00ffa8d049ce2e0c8d9b027ed7bc`) во временный каталог, требует явный текст `SILENT`, запускает R308 без изменений системных файлов и сохраняет сводку только в памяти shell. Затем просит владельца вручную переключить DTS→AC3→DTS и **услышать звук**, требует подтверждение `AUDIBLE`, делает второй read-only снимок и показывает сравнение 13 параметров в терминале. Не переключает дорожки самостоятельно, не устанавливает и не заменяет ни одного плагина, не пишет PCM/фильм/сырые журналы. Временный каталог удаляется автоматически.

**Режим compare:** сравнивает два ранее сохранённых текстовых вывода R308 без сетевого доступа и даже на x86/Linux, но требует корректные метки `STAGE=silent MACHINE=...` и `STAGE=audible MACHINE=...`. Вывод `METRIC=... SILENT=... AUDIBLE=... STATUS=...` и количество отличий; **метрики — наблюдения, не доказательство конкретной причины**.

**Проверка на VPS:** `sh -n` PASS; отказ `capture` на настоящем x86 с exit2 PASS; на искусственных коротких снимках различие `R130_NO_INPUT_CAPS=1→0` и неизменные ALSA/holder определены PASS. Первый вариант парсера был обнаружен как ошибочный полным макетом (метка и число holders находятся на строках с двумя полями); исправлен в commit b473fc8. **Окончательный сквозной mock** с временной подменой только `uname=armv7l` и искусственным journal, реальной SHA-проверкой загружаемого R308, двумя последовательными шагами `SILENT`/`AUDIBLE` и автоматическим сравнением — **PASS**. Макет не является проверкой телевизора. После завершения все тестовые файлы удалены.

**Инженерное решение:** до получения именно такой пары снимков R130-инициализация и маршрутизация native AudioD остаются альтернативными гипотезами. Полная замена R278, произвольный STREAM_START/FLUSH, автоматическая смена AC3/DTS или модификации UMS без физического подтверждения причины не допускаются. Реальная тишина и её устранение переключением пользователем уже воспроизведены; **исправление ещё не внедрено**.

## R311–R312 (2026-11-22): настоящий DTS, сборка кадров, правильный порядок GStreamer — VPS ONLY

- Реальный тест на двух SHA256-проверенных DTS Core-клипах из **оригинального R278** (стерео и 5.1) выявил, что существующий **R188** с новым строго ограниченным анализатором реального DTS-заголовка **восстанавливает полное PCM** при любых блоках 1/11/97/4096 байт. Для обоих форматов 48 128 PCM-кадров; полный SHA256 побайтно совпал с Matroska-эталоном.
- При этом оригинальный экспериментальный Gst-wrapper R188 обнаружил настоящий дефект порядка sticky events: `segment before caps`. Производная **R312** удерживает SEGMENT до фактического согласования выходных CAPS, затем передаёт первый DTS-кадр, очищает ожидание на STREAM_START/FLUSH_STOP и при завершении объекта. Все восемь реальных DTS-проверок **без предупреждений**, плюс **3/3** повреждённых потоков fail closed, **8/8** событий GstPad и **8/8** ASan+UBSan. Исходный R188 не изменён.
- Воспроизводимый [R312 тест](../tools/run-r312-real-dts-ordered-events.sh), финальный commit `7091cbe752822e7f1e6b13a5c5c8b7fc74e5de50`, SHA256 `82afab34a27cb169be4a09a78f260279a16a7fcb77e23571c9488b1d45e24a59`. На VPS повторный реальный запуск с pinned источниками — `RESULT=R312_REAL_DTS_8_OF_8_PCM_3_OF_3_FAIL_CLOSED_EVENTS_8_OF_8_ASAN_8_OF_8_PASS`. SDK заголовки временные, через dpkg-deb -x, системных установок нет. Детали: [отчёт R311/R312](R311_R312_REAL_DTS_FIRST_FRAME_QA.md).
- C99 ядро и анализатор реального заголовка компилируются для ARMv7 softfp (ELF32 ARM EABI5) **только в объектный файл**, но полный ARM GStreamer-плагин пока не собран: нет точного webOS26 GStreamer 1.24.10 sysroot на VPS.
- **Граница вывода:** реальная кухня продолжает использовать R278 (компоненты R130/R239/R56), а **НЕ R188/R312**. Неверная упаковка входного DTS или порядок CAPS/SEGMENT в настоящем кухонном Starfish по-прежнему НЕ ИЗМЕРЕНЫ. По факту пользователь подтвердил «первый DTS после загрузки без звука → AC3 слышен → возврат DTS слышен». Исходная проблема на ТВ НЕ ИСПРАВЛЕНА. Не устанавливать R312 или повышать rank без разрешённых измерений на устройстве и обратимой сборки.
