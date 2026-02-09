# Debian GNOME X11 fractional scaling fix

[Русская версия](docs/README-RU.md)

![Bash](https://img.shields.io/badge/Bash-5.0+-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Debian](https://img.shields.io/badge/Debian-12%2F13-A81D33?style=for-the-badge&logo=debian&logoColor=white)
![GNOME](https://img.shields.io/badge/GNOME-48-4A86CF?style=for-the-badge&logo=gnome&logoColor=white)
![Xorg](https://img.shields.io/badge/Xorg-X11-FF6600?style=for-the-badge&logo=xorg&logoColor=white)
![systemd](https://img.shields.io/badge/systemd-service-DA2525?style=for-the-badge&logo=linux&logoColor=white)

This project builds and installs patched `mutter` and `gnome-control-center` on Debian to enable X11 fractional scaling in GNOME 48. It also provides an optional user service to keep Qt apps in sync with GNOME scaling.

## What is included

- `scripts/fix-scale.sh` - builds and installs patched packages.
- `scripts/qt-scale-watch.sh` - updates `QT_SCALE_FACTOR` based on `~/.config/monitors.xml`.
- `systemd/user/qt-scale-update.path` - watches for monitor scale changes.
- `systemd/user/qt-scale-update.service` - runs the Qt scale update script.
- `install.sh` - installs the fix and optionally the Qt watcher.

## Requirements

- Debian 12 or 13
- GNOME 48
- Xorg session
- `sudo` access for package installation

## Install

```bash
./install.sh
```

Options:

- `--debug` - show full command output (no log files).
- `-y`, `--yes` - auto-accept prompts.
- `--only-qt` - install only the Qt scale watcher and systemd units.

The installer copies `fix-scale` to `~/.local/bin` and, if selected, enables the user systemd path unit for Qt updates.

After installation you must re-login or reboot.

## Run the fix

```bash
./scripts/fix-scale.sh
```

What the script does:

- Installs build tools and build dependencies.
- Downloads Debian source packages with `apt source`.
- Applies X11 fractional scaling patches.
- Builds and installs patched `.deb` packages.
- Enables the GNOME experimental feature `x11-randr-fractional-scaling`.
- Optionally puts `mutter` and `gnome-control-center` on hold.
- Removes the temporary work directory when finished.

## Qt scaling watcher (optional)

When enabled, `qt-scale-watch` updates `QT_SCALE_FACTOR` to match the highest GNOME scale from `~/.config/monitors.xml`. This helps Qt apps avoid blurry or wrong-sized UI after you change scale in GNOME Settings.

The systemd user units are:

- `qt-scale-update.path`
- `qt-scale-update.service`

Check status:

```bash
systemctl --user status qt-scale-update.path
```

## Uninstall

Stop and disable the Qt watcher:

```bash
systemctl --user disable --now qt-scale-update.path
```

Remove installed files:

```bash
rm -f ~/.local/bin/fix-scale
rm -f ~/.local/bin/qt-scale-watch
rm -f ~/.config/systemd/user/qt-scale-update.path
rm -f ~/.config/systemd/user/qt-scale-update.service
systemctl --user daemon-reload
```

If you used package holds, remove them:

```bash
sudo apt-mark unhold mutter gnome-control-center
```

## Logs

By default, installer logs are stored in:

```
~/.cache/debian-fix-install/logs
```

Build logs are stored in the work directory defined by `WORKDIR` (default: `~/debian-x11-scale`).

## Notes

- This is a local build. Future Debian updates for `mutter` and `gnome-control-center` may overwrite the patched packages if not held.
- If you see patch conflicts, update the patch repositories or apply them manually.
