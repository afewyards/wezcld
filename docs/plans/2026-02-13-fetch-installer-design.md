# Fetch-based Installer

## Problem

`install.sh` embeds full copies of `bin/it2` and `bin/wezcld` as heredocs. `scripts/build-installer.sh` regenerates `install.sh` on every release. Three copies of each script exist across the repo.

## Solution

`install.sh` becomes a thin downloader. It fetches `it2`, `wezcld`, and `VERSION` from GitHub release assets at install time.

## Installer flow

1. Query `https://api.github.com/repos/afewyards/wezcld/releases/latest` for latest tag
2. Download `it2`, `wezcld`, `VERSION` from release assets
3. Place in `~/.local/share/wezcld/bin/`
4. Create wrappers in `~/.local/bin/`, configure PATH in shell rc

## Release workflow changes

- Attach `bin/it2`, `bin/wezcld`, `VERSION` as release assets alongside `install.sh`
- Delete `scripts/build-installer.sh` — `install.sh` is now static
- Remove "rebuild installer" step from CI

## What stays the same

- Uninstall logic
- Dependency check (wezterm)
- Wrapper scripts in `~/.local/bin/`
- PATH configuration in shell rc
- `curl -fsSL <url> | sh` pattern
