# For repository maintainers only

Internal instructions for preparing pre-built packages. Not intended for end users.

## 1. Build and create tarball

On Debian 13.3 (or compatible) in an X11 session:

```bash
./scripts/fix-scale.sh --save-debs -y
```

The script will build mutter and gnome-control-center with patches but **will not install** them. It will create a file in `$HOME`, for example:

```
x11-scale-mutter-48.7-0-deb13u1-gcc-48.4-1-deb13u1-amd64.tar.xz
```

## 2. Upload

Upload the tarball as an asset to a GitHub release. The filename must match exactly what the script produced — the installer looks it up by name.

## 3. Naming

For Debian 13.3, expected filename:
```
x11-scale-mutter-48.7-0-deb13u1-gcc-1-48.4-1-deb13u1-amd64.tar.xz
```

Format: `x11-scale-mutter-<mutter_ver>-gcc-<gcc_ver>-<arch>.tar.xz`

Versions come from `apt-cache policy` (Candidate). Symbols `+`, `~`, `:` are replaced with `-` in the filename.

## 4. Tarball structure

All `.deb` files in the root (no subdirs). Created automatically by `--save-debs`.
