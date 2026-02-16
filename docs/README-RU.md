# Исправление дробного масштабирования GNOME X11 для Debian

[English version](../README.md)

![Bash](https://img.shields.io/badge/Bash-5.0+-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Debian](https://img.shields.io/badge/Debian-12%2F13-A81D33?style=for-the-badge&logo=debian&logoColor=white)
![GNOME](https://img.shields.io/badge/GNOME-48-4A86CF?style=for-the-badge&logo=gnome&logoColor=white)
![Xorg](https://img.shields.io/badge/Xorg-X11-FF6600?style=for-the-badge&logo=xorg&logoColor=white)
![systemd](https://img.shields.io/badge/systemd-service-DA2525?style=for-the-badge&logo=linux&logoColor=white)

Проект собирает и устанавливает пропатченные `mutter` и `gnome-control-center` в Debian, чтобы включить дробное масштабирование X11 в GNOME 48. Также есть опциональный пользовательский сервис для синхронизации масштабирования Qt-приложений с GNOME.

## Что внутри

- `scripts/fix-scale.sh` - сборка и установка пропатченных пакетов.
- `scripts/qt-scale-watch.sh` - обновляет `QT_SCALE_FACTOR` по данным из `~/.config/monitors.xml`.
- `systemd/user/qt-scale-update.path` - отслеживает изменения масштаба мониторов.
- `systemd/user/qt-scale-update.service` - запускает скрипт обновления масштаба Qt.
- `install.sh` - установка фикса и (по желанию) Qt-наблюдателя.

## Требования

- Debian 12 или 13
- GNOME 48
- Сессия Xorg
- Доступ к `sudo` для установки пакетов

## Установка

```bash
./install.sh
```

Опции:

- `--debug` - полный вывод команд (без лог-файлов).
- `-y`, `--yes` - автоматически подтверждать запросы.
- `--only-qt` - установить только Qt-наблюдателя и systemd units.

Установщик копирует `fix-scale` в `~/.local/bin` и, при выборе, включает пользовательский systemd path unit для обновлений Qt.

После установки обязательно перелогиньтесь или перезагрузитесь.

## Запуск фикса

```bash
./scripts/fix-scale.sh
```

Что делает скрипт:

- Ищет готовый пакет в [Releases](https://github.com/KroJIak/debian-gnome-x11-fractional-scaling/releases), подходящий под вашу систему (1–2 мин).
- Если нет — собирает из исходников: ставит зависимости, качает исходники, применяет патчи (~30 мин).
- Включает экспериментальную опцию GNOME `x11-randr-fractional-scaling`.
- По желанию ставит `mutter` и `gnome-control-center` на hold.

## Qt-наблюдатель масштаба (опционально)

При включении `qt-scale-watch` обновляет `QT_FONT_DPI` на основе максимального масштаба из `~/.config/monitors.xml`. Это помогает Qt-приложениям сохранить читаемый размер интерфейса после изменения масштаба в настройках GNOME без принудительного глобального масштаба Qt.

Пользовательские systemd units:

- `qt-scale-update.path`
- `qt-scale-update.service`

Проверка статуса:

```bash
systemctl --user status qt-scale-update.path
```

Примечание: для некоторых Qt-приложений на X11 после смены масштаба может понадобиться перелогиниться или перезагрузиться.

## Удаление

Остановить и отключить Qt-наблюдатель:

```bash
systemctl --user disable --now qt-scale-update.path
```

Удалить установленные файлы:

```bash
rm -f ~/.local/bin/fix-scale
rm -f ~/.local/bin/qt-scale-watch
rm -f ~/.config/systemd/user/qt-scale-update.path
rm -f ~/.config/systemd/user/qt-scale-update.service
systemctl --user daemon-reload
```

Если использовали hold, снимите его:

```bash
sudo apt-mark unhold mutter gnome-control-center
```

## Готовые пакеты (быстрая установка)

Если в [Releases](https://github.com/KroJIak/debian-gnome-x11-fractional-scaling/releases) есть готовый архив для ваших версий mutter и gnome-control-center, скрипт скачает и установит его (1–2 мин). Иначе соберёт из исходников (~30 мин).

## Логи

По умолчанию логи установщика хранятся в:

```
~/.cache/debian-fix-install/logs
```

Логи сборки лежат в рабочей директории `WORKDIR` (по умолчанию: `~/debian-x11-scale`).

## Примечания

- Это локальная сборка. Будущие обновления Debian могут перезаписать пропатченные пакеты, если их не держать на hold.
- При конфликтах патчей обновите репозитории патчей или примените их вручную.
