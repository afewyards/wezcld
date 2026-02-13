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
if ! command -v wezterm >/dev/null 2>&1; then
    missing="$missing wezterm"
fi
if [ -n "$missing" ]; then
    printf "${YELLOW}Warning: Missing dependencies:${missing}${NC}\n"
fi

# Create directories
mkdir -p "$INSTALL_DIR/bin" "$BIN_DIR" "$STATE_DIR"

# --- Extract embedded files ---
HEADER

# Embed bin/it2
printf 'cat > "$INSTALL_DIR/bin/it2" << '"'"'IT2_SHIM_EOF'"'"'\n' >> "$OUT"
cat "$REPO_DIR/bin/it2" >> "$OUT"
printf 'IT2_SHIM_EOF\n\n' >> "$OUT"

# Embed bin/wezcld
printf 'cat > "$INSTALL_DIR/bin/wezcld" << '"'"'WEZCLD_EOF'"'"'\n' >> "$OUT"
cat "$REPO_DIR/bin/wezcld" >> "$OUT"
printf 'WEZCLD_EOF\n\n' >> "$OUT"

# Append footer
cat >> "$OUT" << 'FOOTER'
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
echo "  curl -fsSL <url> | sh -s -- --uninstall"
FOOTER

chmod +x "$OUT"
echo "Generated: $OUT"
