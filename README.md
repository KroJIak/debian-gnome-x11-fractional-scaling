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
- `scripts/recovery-restore.sh` - rollback tool to restore original Debian packages.
- `scripts/qt-scale-watch.sh` - updates `QT_SCALE_FACTOR` based on `~/.config/monitors.xml`.
- `systemd/user/qt-scale-update.path` - watches for monitor scale changes.
- `systemd/user/qt-scale-update.service` - runs the Qt scale update script.
- `install.sh` - installs the fix and optionally the Qt watcher and recovery tool.

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

The installer copies `fix-scale` and `recovery-restore` to `~/.local/bin`, prompts to run `fix-scale` (build and install patched mutter/gnome-control-center), and optionally enables the user systemd path unit for Qt updates.

### Safety Features

✓ **Automatic backup** of original `mutter` and `gnome-control-center` packages before patching  
✓ **Patch validation** - fails immediately on conflicts (`.rej` files)  
✓ **Feature verification** - confirms `x11-randr-fractional-scaling` is enabled  
✓ **Safe updates** - preserves other experimental features  
✓ **Package holds** (optional) - prevents apt from overwriting patches  
✓ **Recovery tool** - fast rollback to original Debian packages  

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

When enabled, `qt-scale-watch` updates `QT_FONT_DPI` based on the highest GNOME scale from `~/.config/monitors.xml`. This helps Qt apps keep readable UI sizes after you change scale in GNOME Settings without forcing a global Qt scale.

The systemd user units are:

- `qt-scale-update.path`
- `qt-scale-update.service`

Check status:

```bash
systemctl --user status qt-scale-update.path
```

Note: Some Qt apps may still require re-login or reboot after changing scale to work correctly on X11.

## Uninstall and Recovery

### Quick rollback (if something breaks)

List available backups:

```bash
~/.local/bin/recovery-restore --list
```

Restore from latest backup:

```bash
~/.local/bin/recovery-restore -y
```

Restore from specific backup:

```bash
~/.local/bin/recovery-restore --backup 20250212-164200 -y
```

### Full cleanup

Stop and disable the Qt watcher:

```bash
systemctl --user disable --now qt-scale-update.path
```

Remove installed files:

```bash
rm -f ~/.local/bin/fix-scale
rm -f ~/.local/bin/recovery-restore
rm -f ~/.local/bin/qt-scale-watch
rm -f ~/.config/systemd/user/qt-scale-update.path
rm -f ~/.config/systemd/user/qt-scale-update.service
systemctl --user daemon-reload
```

Remove package holds (if used):

```bash
sudo apt-mark unhold mutter gnome-control-center
```

## Logs and Backup Storage

Installer logs:

```
~/.cache/debian-fix-install/logs
```

Original package backups:

```
~/.local/share/debian-fix-backup/
```

Build logs:

```
~/debian-x11-scale/logs (WORKDIR/logs)
```

## Debian 13.3 / mutter 48.7

On Debian 13.3 with mutter 48.7, the script now prefers the **Ubuntu Salsa** patch (maintained for newer mutter) over the archived puxplaying patch. If the Ubuntu patch fails to apply, the puxplaying patch is tried automatically. Ensure `dpkg-dev` is installed (pulled in via `devscripts`).

## Important Notes

- **Backups are essential**: Before each patch, original packages are backed up automatically.
- **Package holds recommended**: To prevent apt updates from overwriting your patches, the installer will ask to enable holds.
- **If apt overwrites patches**: Use `recovery-restore` to quickly rollback and re-run `fix-scale.sh`.
- **Version requirements**: Script enforces Debian 12/13 and GNOME 48 checks; can override with prompts.
- **Session requirement**: Must be running Xorg (X11), not Wayland.
- **Build tool requirement**: Needs `quilt` for patch application (auto-installed).
- **Partial build failures**: If one package fails, you can fix and rebuild just that package separately.
- **Qt apps note**: Some Qt applications may require re-login or reboot to fully sync with new scaling.
