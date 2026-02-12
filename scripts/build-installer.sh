#!/bin/sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="$REPO_DIR/install.sh"

cat > "$OUT" << 'HEADER'
#!/bin/sh
set -eu

# wezcld installer
# Run: curl -fsSL <url> | sh
# Uninstall: curl -fsSL <url> | sh -s -- --uninstall

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
    rm -f "$BIN_DIR/wezcld" "$BIN_DIR/tmux"
    rm -rf "$INSTALL_DIR"
    rm -rf "$STATE_DIR"
    # Remove PATH line from shell rc files
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
if ! command -v jq >/dev/null 2>&1; then
    missing="$missing jq"
fi
if ! command -v wezterm >/dev/null 2>&1; then
    missing="$missing wezterm"
fi
if [ -n "$missing" ]; then
    printf "${YELLOW}Warning: Missing dependencies:${missing}${NC}\n"
    printf "${YELLOW}Install with: brew install${missing}${NC}\n"
fi

# Find real tmux in PATH (skip BIN_DIR)
REAL_TMUX=""
saved_ifs="$IFS"
IFS=:
for path_entry in $PATH; do
    IFS="$saved_ifs"
    if [ "$path_entry" = "$BIN_DIR" ]; then
        continue
    fi
    if [ -x "$path_entry/tmux" ]; then
        REAL_TMUX="$path_entry/tmux"
        break
    fi
done
IFS="$saved_ifs"

# Create directories
mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/lib" "$BIN_DIR" "$STATE_DIR"

# Save real tmux path
if [ -n "$REAL_TMUX" ]; then
    echo "$REAL_TMUX" > "$STATE_DIR/real-tmux-path"
    printf "${GREEN}Real tmux found at: ${REAL_TMUX}${NC}\n"
else
    printf "${YELLOW}Warning: Real tmux not found in PATH${NC}\n"
fi

# --- Extract embedded files ---
HEADER

# Embed pane-map.sh
printf 'cat > "$INSTALL_DIR/lib/pane-map.sh" << '"'"'PANE_MAP_EOF'"'"'\n' >> "$OUT"
cat "$REPO_DIR/lib/pane-map.sh" >> "$OUT"
printf 'PANE_MAP_EOF\n\n' >> "$OUT"

# Embed bin/tmux
printf 'cat > "$INSTALL_DIR/bin/tmux" << '"'"'TMUX_SHIM_EOF'"'"'\n' >> "$OUT"
cat "$REPO_DIR/bin/tmux" >> "$OUT"
printf 'TMUX_SHIM_EOF\n\n' >> "$OUT"

# Embed bin/wezcld
printf 'cat > "$INSTALL_DIR/bin/wezcld" << '"'"'WEZCLD_EOF'"'"'\n' >> "$OUT"
cat "$REPO_DIR/bin/wezcld" >> "$OUT"
printf 'WEZCLD_EOF\n\n' >> "$OUT"

# Append footer
cat >> "$OUT" << 'FOOTER'
# Make scripts executable
chmod +x "$INSTALL_DIR/bin/wezcld" "$INSTALL_DIR/bin/tmux" "$INSTALL_DIR/lib/pane-map.sh"

# Create thin wrappers in BIN_DIR
cat > "$BIN_DIR/wezcld" << 'WRAPPER_WEZCLD'
#!/bin/sh
exec "$HOME/.local/share/wezcld/bin/wezcld" "$@"
WRAPPER_WEZCLD
chmod +x "$BIN_DIR/wezcld"

cat > "$BIN_DIR/tmux" << 'WRAPPER_TMUX'
#!/bin/sh
exec "$HOME/.local/share/wezcld/bin/tmux" "$@"
WRAPPER_TMUX
chmod +x "$BIN_DIR/tmux"

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
        # Try both if shell is unknown
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
echo "The tmux shim is active when running inside WezTerm."
echo "Outside WezTerm, all tmux commands pass through to the real tmux."
echo ""
echo "To uninstall:"
echo "  curl -fsSL <url> | sh -s -- --uninstall"
FOOTER

chmod +x "$OUT"
echo "Generated: $OUT"
