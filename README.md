# AlekS DTS для LG webOS

[English](README.en.md) · [Лицензия документации](LICENSE.md)

> **R278 доступен для установки** на LG 65NANO896PC с прошивкой 03.60.96. [Команда установки](#как-установить)

**AlekS DTS R277** добавляет декодирование DTS Core в штатный медиатракт LG webOS. При обычном включении телевизора поддержка загружается автоматически. Для проверенной дорожки DTS 5.1 медиаплеер получил PCM S16LE, 48 кГц, 6 каналов.

## Что проверено

| Устройство и сценарий | Результат |
| --- | --- |
| LG 65NANO896PC, webOS TV 6.6.0, ARMv7 | R277 загрузился после перезагрузки телевизора |
| Штатный медиаплеер | Исходный DTS Core 5.1 воспроизвёлся до конца. Звук подтверждён прослушиванием |
| Lampa | Звук был слышен на всех прослушанных дорожках, включая русские DTS 5.1 и FLAC 2.0 |
| Контрольные проверки | Файл AC3 5.1 воспроизвёлся до конца. DVB-C прошёл проверку до и после DTS |

DTS Core 2.0 и 5.1 также прошли изолированные тесты. Для DTS-HD MA, DTS:X, передачи DTS на ресивер и других моделей LG нужна отдельная проверка.

## Совместимость R277

| Модель или платформа | Статус |
| --- | --- |
| LG 65NANO896PC · прошивка 03.60.96 · webOS TV 6.6.0 · ARMv7 · GStreamer 1.16.2 | Проверено на телевизоре с root-доступом и уже установленным R56 |
| Другие LG на webOS TV 6.x, ARMv7 | Кандидаты на проверку. Нужно сверить модель, прошивку, ABI GStreamer и работу штатного медиаплеера и Live TV |
| webOS TV 5.x и линейки webOS TV 22–26 | R277 на этих версиях не проверен. Для ARM64 требуется отдельная сборка и испытания штатного медиатракта |

Перед установкой воспроизведите в штатном плеере локальный MKV с известной дорожкой DTS Core. Если звук уже есть, для этой дорожки установка не нужна. По одному номеру webOS нельзя определить поддержку DTS и совместимость R277. [Спецификации LG webOS TV](https://webostv.developer.lge.com/develop/specifications)

## Как установить

На **LG 65NANO896PC с прошивкой 03.60.96 и webOS TV 6.6.0** заранее настройте root SSH и Homebrew. Откройте SSH-сеанс на телевизоре и вставьте весь блок. После сообщения `R278 configured` полностью перезагрузите ТВ.

```sh
(
  set -eu
  [ "$(id -u)" = 0 ] || { echo 'Root SSH is required.' >&2; exit 1; }
  [ "$(uname -m)" = armv7l ] || { echo 'This release requires ARMv7.' >&2; exit 1; }
  stage=$(mktemp -d /tmp/aleks-dts-download.XXXXXX)
  trap 'rm -rf -- "$stage"' EXIT
  cd "$stage"
  curl -fLsS --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 120 \
    -o release.tar.gz 'https://raw.githubusercontent.com/aerolit266/AlekS-DTS-webOS/main/downloads/r278/AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz'
  printf '%s  %s\n' 'cafb3e014f407a4a0dda6bd50a0e4f983aa0b35ea1f53e705f504aed0a094ea1' release.tar.gz | sha256sum -c -
  tar -xmzf release.tar.gz
  sh ./install.sh install
)
```

Для отката выполните `sh /var/lib/webosbrew/aleks-dts-r278/install.sh rollback` и полностью перезагрузите ТВ.

[Установочный архив](downloads/r278/AlekS-DTS-R278-65NANO896PC-03.60.96.tar.gz) · [SHA‑256](downloads/r278/SHA256SUMS) · [Лицензии ПО](downloads/r278/SOFTWARE-NOTICES.txt) · [libdcadec и перелинковка](downloads/r278/R278-R56-LGPL-RELINK.tar.gz)

Оригинальный установщик проверен на чистой конфигурации медиасервера. Очищенные плагины из публичного комплекта прошли изолированные тесты DTS 2.0, DTS 5.1 и AC3 на том же LG. Если модель или прошивка отличаются, укажите их в [запросе совместимости](https://github.com/aerolit266/AlekS-DTS-webOS/issues/new).


© 2026 AlekS / GameFree24 (@aerolit266). [Условия использования документации](LICENSE.md).
