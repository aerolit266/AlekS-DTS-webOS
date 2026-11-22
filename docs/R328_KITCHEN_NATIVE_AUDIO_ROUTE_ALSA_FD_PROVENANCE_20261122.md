# R328 — кухонный LG: устройство ALSA, `audiooutputd` и реальный путь DTS

**Дата:** 22 ноября 2026 года. **ПРОВЕРЕНО на физическом LG** без изменения системы; акустическое состояние в момент R328: **UNCLASSIFIED**. Исходная проблема «первый DTS после перезапуска без звука; после AC3→DTS звук появляется» подтверждена владельцем ранее, включая реальную пару [R327](R327_REAL_OWNER_DTS_SILENT_AUDIBLE_MONITOR_LIMITATION_20261122.md), но **первопричина остаётся неизвестной**.

## Что именно проверено

Повторно использована существующая авторизованная цепочка **GameFree24 VPS MCP V3 → AlekS Core → TORMOZ → `aleks-kitchen-root`**. На телевизор временно загружен SHA256-проверенный диагностический скрипт [`tools/r328-native-audio-route-readonly.py`](../tools/r328-native-audio-route-readonly.py); никакой перезапуск или изменение системных служб, DLL, GStreamer, микшеров, каналов или драйверов не проводились.

Итоговый точно исполненный скрипт из коммита `56eb8d14b7cd27ef2b9319ab8cc9aebc4423828a`, SHA256 `fee9f6b1db7eb702b116794a2cb15f4f22b0af07f708ba48fefe68a8b2c3c1c0`. На VPS и LG Python selftest PASS, чтение на LG через задачу `75c88cc5ccfb135ccb02577d8885c088` завершилось `COMPLETED`, exit0, `RESULT=R328_NATIVE_ROUTE_READONLY_PASS`. Исходные данные по одному моменту сохранены как **UNCLASSIFIED**, только в приватный файл с режимом `0600`:

`/opt/gamefree24-vps-mcp/private/dts-r328-20261122/kitchen-native-route-unclassified.json`

SHA256 `822ad0a9f3e06c86d66162ab385289201cf060d0a05884280759172c7a62d09f`, 2 392 байта. Поля ограничены известными кодеком, состояниями LS2, числом процессов/дескрипторов, именами штатных ALSA PCM/control и наличием диагностических интерфейсов. **Звуковые данные, названия фильмов, URL, журнал процессов и секреты не сохранялись**.

## Реальные устройства ALSA и владельцы

| Процесс | Дескрипторы `/dev/snd` | **Фактические имена узлов** | Значение |
|---|---:|---|---|
| `audiooutputd` | 3 | **только `controlC0`** | Дескрипторы управляющего ALSA interface, **не PCM-вывод** |
| `pulseaudio` | 2 | `pcmC0D6p` и `timer` | Явный открытый PCM playback sink + timer |
| `starfish-media-` (2 процесса) | 0 | нет | Нет прямых дескрипторов ALSA у этих процессов; не исключает косвенное аудио |
| `umediaserver` | 0 | нет | Управление media |

`/proc/asound/cards` показывает **две карты Mars**, а `/proc/asound/card0/pcm6p/sub0/status` — `RUNNING`, владельцем является поток `alsa-sink-MARS` процесса `pulseaudio`. `hw_ptr` и `appl_ptr` существуют, но они **не гарантируют ненулевой звук**, как уже показал R327. Других запущенных PCM playback-узлов в рассматриваемом наборе card0/pcm0..7 нет.

Загружены `libasound.so` у `audiooutputd` и `pulseaudio`, `libgstreamer-1.0.so` у обоих Starfish-процессов. В одном процессе Starfish отображена оригинальная `libgstaleksdts16dec.so` R278; **наличие библиотеки в `/proc/*/maps` не доказывает успешный декодинг текущих DTS-фреймов**.

**Важная коррекция предварительной гипотезы:** из наличия трёх дескрипторов `/dev/snd` у `audiooutputd` нельзя делать вывод о втором PCM-потоке: три FD относятся к **`controlC0`**, а **PCM6 открыт PulseAudio**. `audiooutputd` может управлять маршрутом без собственного PCM-дескриптора; работа иных собственных LG/DSP интерфейсов не исследована.

## Статус нативного маршрута LS2

Только штатные read-only методы `getStatus`, `getStreamStatus`, `getSoundOutput` и `getAudioInputProperty`, без управления аудио.

- `com.webos.service.audiooutput/audio/getStatus`: **ровно одна связь `ADEC0 → MAIN`**, `muted=false`, `outputMode=null`.
- `com.webos.service.audio/tv/getAudioInputProperty`: **`codec=dts`** в одном поле.
- `com.webos.service.audio/getSoundOutput`: `tv_external_speaker`.
- `com.webos.service.audio/getStreamStatus`: 2 объекта, оба `activeStatus=true`, 0 объектов с `policyStatus=true`.
- `/sys/kernel/debug` и `/sys/kernel/tracing/events` существуют, но **верхнеуровневые имена групп**, начинающиеся с `audio`, `asoc`, `snd`, `sound`, `codec` или `dsp`, не обнаружены; `/sys/kernel/debug/asoc` отсутствует. **Трассировка не включалась и содержимое trace buffer не читалось.** Это не доказывает полное отсутствие собственных диагностических интерфейсов LG.

[Официальный LS2 audiooutput getStatus webOS OSE](https://www.webosose.org/docs/reference/ls2-api/com-webos-service-audiooutput/) описывает **состояние маршрута** (`source`, `sink`, `muted`, `outputMode`), а не амплитуду, PTS или число успешно отданных DTS кадров. Референс OSE не является подтверждением идентичности приватной реализации LG webOS TV, но совпадает с наблюдаемой структурой ответа.

## Что пока НЕ доказано и что требуется для исправления

- [R327](R327_REAL_OWNER_DTS_SILENT_AUDIBLE_MONITOR_LIMITATION_20261122.md) **подтвердил реальную пару**: владелец слышал тишину, потом звук, но `pcm_output.monitor` отдал цифровой ноль в **обоих** состояниях. Он не пригоден как DTS-амплитудометр; даже в слышимом состоянии не видно сигнала. Не утверждать «PCM пропадает до PulseAudio» по этому измерению.
- Последний R328 снимок не помечался владельцем как `silent` или `audible`; сравнение его с R327 не даёт новой причинной информации.
- Процессы и LS2 getter не раскрывают **`GstBuffer`/DTS frame boundary/`SEGMENT`/`CAPS`** внутри Starfish, результата `dcadec_context_parse/filter` или реальной PCM RMS **до native audio handoff**.
- Успешный [R325 изолированный стенд](R325_KITCHEN_DTS_TIME_SEGMENT_NATIVE_20261122.md) по исправлению `BYTE→TIME` и кадровой сборке **не доказывает**, что Lampa передаёт DTS с неправильным сегментом при холодном запуске.
- Следующий обоснованный этап — **подготовить вне рабочего медиапроцесса ограниченный, конфиденциальный pad-level счетчик**: `STREAM_START / CAPS / SEGMENT`, число полных/частичных DTS кадров, количество реально выданных PCM кадров, агрегат RMS/peak без самих PCM байтов. Сначала изолированная лаборатория, затем только после отдельного разрешения владельца — временное, обратимое наблюдение первого запуска в Starfish с заранее сохранёнными четырьмя библиотеками и рабочим `umediaserver.env`. **Не подключать скрипт к Lampa/Starfish или критическим LG службам без согласования и плана отката.**

## Сводка

**R328 read-only source/device routing: ПРОВЕРЕНО.** **Не было новой физической пары «тишина→звук» в этом этапе.** Второй ALSA PCM у `audiooutputd`: **не обнаружен**. Прямой доступ Starfish к PCM: **не обнаружен**. Нативный LS2-маршрут есть, но сигнальная амплитуда и начальные события в нём остаются недоступны без дополнительного инструмента. **Реальная причина холодной тишины DTS и постоянное исправление: НЕ ПРОВЕРЕНЫ / НЕ УСТАНОВЛЕНЫ.**
