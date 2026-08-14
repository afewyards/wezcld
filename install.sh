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

# Drop wezcld's PATH line from a shell rc file.
#
# Written through the original file rather than moved over it: an rc file is
# very often a symlink into a dotfiles repo, and `mv` would replace the link
# with a regular file and reset its mode. A backup is kept either way, and a
# real grep failure leaves the file untouched instead of truncating it.
strip_wezcld_lines() {
    rc_file="$1"
    [ -f "$rc_file" ] || return 0
    grep -q '# wezcld$' "$rc_file" 2>/dev/null || return 0

    tmp="${rc_file}.wezcld-tmp.$$"
    status=0
    grep -v '# wezcld$' "$rc_file" > "$tmp" 2>/dev/null || status=$?
    # grep exits 1 when it selects no lines at all, which is not an error here.
    if [ "$status" -gt 1 ]; then
        rm -f "$tmp"
        printf "%s\n" "Warning: could not edit $rc_file; remove the '# wezcld' line by hand." >&2
        return 0
    fi

    cp "$rc_file" "${rc_file}.wezcld-backup"
    cat "$tmp" > "$rc_file"
    rm -f "$tmp"
    printf "%s\n" "Removed PATH line from $rc_file (backup: ${rc_file}.wezcld-backup)"
}

# --- Uninstall ---
if [ "${1:-}" = "--uninstall" ]; then
    echo "Uninstalling wezcld..."
    rm -f "$BIN_DIR/wezcld"
    # Older versions also installed an `it2` wrapper here. Only remove it if it
    # is ours — iTerm2 ships a real `it2` that users may have put on PATH.
    if [ -f "$BIN_DIR/it2" ] && grep -q 'wezcld' "$BIN_DIR/it2" 2>/dev/null; then
        rm -f "$BIN_DIR/it2"
    fi
    rm -rf "$INSTALL_DIR"
    rm -rf "$STATE_DIR"
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        strip_wezcld_lines "$rc"
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
    printf "${YELLOW}%s${NC}\n" "Warning: Missing dependencies:$missing"
fi

# Create directories. STATE_DIR holds the it2 call log, which records the
# command text sent to agent panes, so keep it private to the user.
mkdir -p "$INSTALL_DIR/bin" "$BIN_DIR" "$STATE_DIR"
chmod 700 "$STATE_DIR" 2>/dev/null || true

# Download files from latest release
download() {
    file="$1"
    dest="$2"
    if ! curl -fsSL "$BASE_URL/$file" -o "$dest"; then
        printf "${RED}%s${NC}\n" "Error: Failed to download $file"
        exit 1
    fi
}

download "it2" "$INSTALL_DIR/bin/it2"
download "wezcld" "$INSTALL_DIR/bin/wezcld"

# Make scripts executable
chmod +x "$INSTALL_DIR/bin/wezcld" "$INSTALL_DIR/bin/it2"

# Only `wezcld` goes on the user's PATH. The it2 shim stays in INSTALL_DIR and
# is reached through the PATH entry wezcld adds for its own child processes, so
# it can never shadow — or overwrite — a real iTerm2 `it2` the user installed.
rm -f "$BIN_DIR/wezcld"
if [ -f "$BIN_DIR/it2" ] && grep -q 'wezcld' "$BIN_DIR/it2" 2>/dev/null; then
    rm -f "$BIN_DIR/it2"   # leftover wrapper from an older wezcld
fi

# Create thin wrapper in BIN_DIR
cat > "$BIN_DIR/wezcld" << 'WRAPPER_WEZCLD'
#!/bin/sh
exec "$HOME/.local/share/wezcld/bin/wezcld" "$@"
WRAPPER_WEZCLD
chmod +x "$BIN_DIR/wezcld"

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
echo "The it2 shim is scoped to wezcld's own process tree; nothing named it2"
echo "is added to your PATH."
echo "Outside WezTerm, wezcld falls back to plain claude."
echo ""
echo "To uninstall:"
echo "  curl -fsSL $BASE_URL/install.sh | sh -s -- --uninstall"
