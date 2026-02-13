# Fetch-based Installer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the heredoc-embedding installer with one that downloads files from GitHub release assets at install time.

**Architecture:** `install.sh` becomes a static, thin downloader. It uses `https://github.com/afewyards/wezcld/releases/latest/download/<file>` to fetch `it2`, `wezcld`, and `VERSION`. Release workflow attaches these as assets.

**Tech Stack:** POSIX sh, curl, GitHub Releases API (latest/download redirect)

---

### Task 1: Rewrite `install.sh` as a fetch-based downloader

**Files:**
- Modify: `install.sh` (full rewrite)

**Step 1: Rewrite install.sh**

Replace entire file with:

```sh
#!/bin/sh
set -eu

# wezcld installer
# Run: curl -fsSL https://github.com/afewyards/wezcld/releases/latest/download/install.sh | sh
# Uninstall: curl -fsSL https://github.com/afewyards/wezcld/releases/latest/download/install.sh | sh -s -- --uninstall

REPO="afewyards/wezcld"
BASE_URL="https://github.com/$REPO/releases/latest/download"
INSTALL_DIR="$HOME/.local/share/wezcld"
BIN_DIR="$HOME/.local/bin"
STATE_DIR="$HOME/.local/state/wezcld"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- Uninstall ---
if [ "${1:-}" = "--uninstall" ]; then
    echo "Uninstalling wezcld..."
    rm -f "$BIN_DIR/wezcld" "$BIN_DIR/it2"
    rm -rf "$INSTALL_DIR"
    rm -rf "$STATE_DIR"
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -f "$rc" ]; then
            tmp="${rc}.wezcld-tmp"
            grep -v '# wezcld$' "$rc" > "$tmp" || true
            mv "$tmp" "$rc"
        fi
    done
    printf "${GREEN}wezcld uninstalled.${NC}\n"
    exit 0
fi

# --- Install ---
echo "Installing wezcld..."

# Check dependencies
missing=""
if ! command -v curl >/dev/null 2>&1; then
    printf "${RED}Error: curl is required but not found.${NC}\n"
    exit 1
fi
if ! command -v wezterm >/dev/null 2>&1; then
    missing="$missing wezterm"
fi
if [ -n "$missing" ]; then
    printf "${YELLOW}Warning: Missing dependencies:${missing}${NC}\n"
fi

# Create directories
mkdir -p "$INSTALL_DIR/bin" "$BIN_DIR" "$STATE_DIR"

# Download files from latest release
download() {
    file="$1"
    dest="$2"
    if ! curl -fsSL "$BASE_URL/$file" -o "$dest"; then
        printf "${RED}Error: Failed to download $file${NC}\n"
        exit 1
    fi
}

download "it2" "$INSTALL_DIR/bin/it2"
download "wezcld" "$INSTALL_DIR/bin/wezcld"
download "VERSION" "$INSTALL_DIR/VERSION"

# Make scripts executable
chmod +x "$INSTALL_DIR/bin/wezcld" "$INSTALL_DIR/bin/it2"

# Remove old symlinks/files before creating wrappers
rm -f "$BIN_DIR/wezcld" "$BIN_DIR/it2" "$BIN_DIR/tmux"

# Create thin wrappers in BIN_DIR
cat > "$BIN_DIR/wezcld" << 'WRAPPER_WEZCLD'
#!/bin/sh
exec "$HOME/.local/share/wezcld/bin/wezcld" "$@"
WRAPPER_WEZCLD
chmod +x "$BIN_DIR/wezcld"

cat > "$BIN_DIR/it2" << 'WRAPPER_IT2'
#!/bin/sh
exec "$HOME/.local/share/wezcld/bin/it2" "$@"
WRAPPER_IT2
chmod +x "$BIN_DIR/it2"

# Auto-configure shell rc
path_line='export PATH="$HOME/.local/bin:$PATH" # wezcld'

add_to_rc() {
    rc_file="$1"
    if [ -f "$rc_file" ]; then
        if ! grep -q '# wezcld$' "$rc_file"; then
            echo "$path_line" >> "$rc_file"
            printf "${GREEN}Added PATH to ${rc_file}${NC}\n"
        fi
    fi
}

case "${SHELL:-/bin/sh}" in
    */zsh)  add_to_rc "$HOME/.zshrc" ;;
    */bash) add_to_rc "$HOME/.bashrc" ;;
    *)
        [ -f "$HOME/.zshrc" ] && add_to_rc "$HOME/.zshrc"
        [ -f "$HOME/.bashrc" ] && add_to_rc "$HOME/.bashrc"
        ;;
esac

echo ""
printf "${GREEN}Installation complete!${NC}\n"
echo ""
echo "Usage:"
echo "  wezcld                  Launch Claude Code with WezTerm integration"
echo "  wezcld --resume         Resume last session"
echo ""
echo "The it2 shim captures commands when running inside WezTerm."
echo "Outside WezTerm, wezcld falls back to plain claude."
echo ""
echo "To uninstall:"
echo "  curl -fsSL $BASE_URL/install.sh | sh -s -- --uninstall"
```

**Step 2: Verify shell syntax**

Run: `sh -n install.sh`
Expected: no output (valid syntax)

**Step 3: Commit**

```
feat(installer): rewrite as fetch-based downloader

Downloads bin/it2, bin/wezcld, VERSION from GitHub release
assets instead of embedding them as heredocs.
```

---

### Task 2: Update release workflow to attach source files as assets

**Files:**
- Modify: `.github/workflows/release.yml`

**Step 1: Update release.yml**

Replace the "Update VERSION and rebuild installer" step — remove `sh scripts/build-installer.sh` and `git add install.sh`:

```yaml
      - name: Update VERSION file
        if: steps.semrel.outputs.version != ''
        run: |
          echo "${{ steps.semrel.outputs.version }}" > VERSION
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add VERSION
          git commit -m "chore(release): ${{ steps.semrel.outputs.version }} [skip ci]"
          git push
```

Update the "Create GitHub Release" step — add `bin/it2`, `bin/wezcld`, `VERSION`:

```yaml
      - name: Create GitHub Release
        if: steps.semrel.outputs.version != ''
        uses: softprops/action-gh-release@v2
        with:
          tag_name: v${{ steps.semrel.outputs.version }}
          files: |
            install.sh
            bin/it2
            bin/wezcld
            VERSION
          generate_release_notes: true
```

**Step 2: Commit**

```
chore(ci): attach source files as release assets
```

---

### Task 3: Delete `scripts/build-installer.sh`

**Files:**
- Delete: `scripts/build-installer.sh`

**Step 1: Remove the file**

```bash
rm scripts/build-installer.sh
```

**Step 2: Commit**

```
chore: remove build-installer.sh (no longer needed)
```
