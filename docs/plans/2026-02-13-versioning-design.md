# Automatic Versioning Design

## Overview

Add automatic semantic versioning to wezcld using go-semantic-release. Version callable via `wezcld --version`.

## Approach

VERSION file committed to repo root by go-semantic-release. `wezcld --version` reads it at runtime. Installer embeds it alongside bin/ scripts.

## Components

### 1. `wezcld --version` / `-v`

Added after `--uninstall` check, before WezTerm detection. Reads `$SHIM_DIR/VERSION`, falls back to `dev`.

```sh
if [ "${1:-}" = "--version" ] || [ "${1:-}" = "-v" ]; then
    VER="dev"
    [ -f "$SHIM_DIR/VERSION" ] && VER="$(cat "$SHIM_DIR/VERSION")"
    echo "wezcld $VER"
    exit 0
fi
```

### 2. VERSION file

- Lives at repo root, contains bare version string (e.g. `0.3.0`)
- Updated by go-semantic-release on each release
- Initial value: `0.1.0` (or whatever first release produces)

### 3. build-installer.sh changes

Embed VERSION into install.sh alongside bin/ files:

```sh
printf 'cat > "$INSTALL_DIR/VERSION" << '"'"'VERSION_EOF'"'"'\n' >> "$OUT"
cat "$REPO_DIR/VERSION" >> "$OUT"
printf 'VERSION_EOF\n\n' >> "$OUT"
```

Installed path: `~/.local/share/wezcld/VERSION`

### 4. GitHub Actions release workflow

File: `.github/workflows/release.yml`

Trigger: push to `main`

Steps:
1. Checkout with full history
2. `go-semantic-release/action@v1` — determines next version from conventional commits
3. If new version: write VERSION, run build-installer.sh
4. Create GitHub Release via `softprops/action-gh-release@v2`, attach install.sh

Conventional commit mapping: `fix:` = patch, `feat:` = minor, `feat!:` / `BREAKING CHANGE` = major.

Release commit uses `[skip ci]` to avoid loop.

### 5. Path resolution

`$SHIM_DIR` already resolves to parent of `bin/`:
- Installed: `~/.local/share/wezcld` → `$SHIM_DIR/VERSION` works
- Dev/clone: repo root → `$SHIM_DIR/VERSION` works

No path changes needed.

### 6. Testing

Add to `tests/integration-test.sh`:
- `wezcld --version` outputs `wezcld <something>`
- `wezcld -v` same behavior
- With mock VERSION file: outputs `wezcld 1.2.3`
- Without VERSION file: outputs `wezcld dev`
