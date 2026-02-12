#!/usr/bin/env bash
set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Resolve the directory where this script lives
SHIM_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing WezTerm tmux shim from: $SHIM_DIR"

# Ensure ~/.local/bin exists
mkdir -p "$HOME/.local/bin"

# Ensure state directory exists
STATE_DIR="$HOME/.local/state/wezterm-tmux-shim"
mkdir -p "$STATE_DIR"

# Detect real tmux
echo "Detecting real tmux installation..."
REAL_TMUX=""
IFS=: read -ra path_entries <<< "$PATH"
for path_entry in "${path_entries[@]}"; do
    # Skip our shim directory
    if [[ "$path_entry" == "$HOME/.local/bin" ]]; then
        continue
    fi

    if [[ -x "$path_entry/tmux" ]]; then
        REAL_TMUX="$path_entry/tmux"
        break
    fi
done

if [[ -n "$REAL_TMUX" ]]; then
    echo "$REAL_TMUX" > "$STATE_DIR/real-tmux-path"
    echo -e "${GREEN}Real tmux found at: $REAL_TMUX${NC}"
else
    echo -e "${YELLOW}Warning: Real tmux not found in PATH${NC}"
    echo -e "${YELLOW}The shim will still be installed, but won't have a fallback${NC}"
fi

# Check dependencies
echo "Checking dependencies..."
MISSING_DEPS=()

if ! command -v jq &> /dev/null; then
    MISSING_DEPS+=("jq")
fi

if ! command -v wezterm &> /dev/null; then
    MISSING_DEPS+=("wezterm")
fi

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    echo -e "${YELLOW}Warning: Missing dependencies: ${MISSING_DEPS[*]}${NC}"
    echo -e "${YELLOW}Install with: brew install ${MISSING_DEPS[*]}${NC}"
fi

# Create symlinks (idempotent)
echo "Creating symlinks..."
ln -sf "$SHIM_DIR/bin/wezcld" "$HOME/.local/bin/wezcld"
ln -sf "$SHIM_DIR/bin/tmux" "$HOME/.local/bin/tmux"
echo -e "${GREEN}Symlinks created${NC}"

# Verify PATH order
echo "Verifying PATH configuration..."
PATH_OK=false
if [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
    if [[ -n "$REAL_TMUX" ]]; then
        REAL_TMUX_DIR="$(dirname "$REAL_TMUX")"
        # Check if ~/.local/bin appears before real tmux directory
        if [[ "$PATH" =~ $HOME/.local/bin.*$REAL_TMUX_DIR ]]; then
            PATH_OK=true
        fi
    else
        PATH_OK=true
    fi
fi

if $PATH_OK; then
    echo -e "${GREEN}PATH is configured correctly${NC}"
else
    echo -e "${YELLOW}Warning: ~/.local/bin may not be early enough in PATH${NC}"
    echo -e "${YELLOW}Add this to your shell profile:${NC}"
    echo -e "${YELLOW}  export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
fi

# Print success and usage
echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "Usage:"
echo "  wezcld                  Launch Claude Code with WezTerm integration"
echo "  wezcld --resume         Resume last session"
echo ""
echo "The tmux shim is active when running inside WezTerm."
echo "Outside WezTerm, all tmux commands pass through to the real tmux."
echo ""
echo "To uninstall:"
echo "  rm ~/.local/bin/wezcld ~/.local/bin/tmux"
