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
cat > "$INSTALL_DIR/lib/pane-map.sh" << 'PANE_MAP_EOF'
#!/bin/sh

# Library for mapping tmux-style pane IDs (%N) to WezTerm integer pane IDs

STATE_DIR="${WEZTERM_SHIM_STATE:-$HOME/.local/state/wezcld}"
PANE_MAP="${STATE_DIR}/pane-map"
COUNTER="${STATE_DIR}/counter"
LOCK_DIR="${STATE_DIR}/counter.lock"
LOCK_TIMEOUT=50  # attempts (x0.1s = 5 seconds)

shim_init() {
    mkdir -p "$STATE_DIR"
    if [ ! -f "$COUNTER" ]; then
        echo "0" > "$COUNTER"
    fi
    if [ ! -f "$PANE_MAP" ]; then
        touch "$PANE_MAP"
    fi
}

_acquire_lock() {
    attempts=0
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        attempts=$((attempts + 1))
        if [ "$attempts" -ge "$LOCK_TIMEOUT" ]; then
            echo "Failed to acquire lock after ${LOCK_TIMEOUT} attempts" >&2
            return 1
        fi
        sleep 0.1
    done
    return 0
}

_release_lock() {
    rmdir "$LOCK_DIR" 2>/dev/null
}

alloc_pane_id() {
    wez_id="$1"
    tab_id="$2"
    if [ -z "$wez_id" ] || [ -z "$tab_id" ]; then
        echo "Usage: alloc_pane_id <wez_id> <tab_id>" >&2
        return 1
    fi
    if ! _acquire_lock; then
        return 1
    fi
    counter=$(cat "$COUNTER" 2>/dev/null || echo "0")
    next_id=$((counter + 1))
    echo "$next_id" > "$COUNTER"
    _release_lock
    tmux_id="%${counter}"
    echo "$tmux_id $wez_id $tab_id" >> "$PANE_MAP"
    echo "$tmux_id"
}

wez_from_tmux() {
    _tmux_id="$1"
    if [ -z "$_tmux_id" ]; then
        echo "Usage: wez_from_tmux <tmux_id>" >&2
        return 1
    fi
    result=$(awk -v tid="$_tmux_id" '$1 == tid {print $2; exit}' "$PANE_MAP")
    if [ -z "$result" ]; then
        return 1
    fi
    echo "$result"
}

tmux_from_wez() {
    _wez_id="$1"
    if [ -z "$_wez_id" ]; then
        echo "Usage: tmux_from_wez <wez_id>" >&2
        return 1
    fi
    result=$(awk -v wid="$_wez_id" '$2 == wid {print $1; exit}' "$PANE_MAP")
    if [ -z "$result" ]; then
        return 1
    fi
    echo "$result"
}

remove_pane() {
    _tmux_id="$1"
    if [ -z "$_tmux_id" ]; then
        echo "Usage: remove_pane <tmux_id>" >&2
        return 1
    fi
    tmp="${PANE_MAP}.tmp"
    awk -v tid="$_tmux_id" '$1 != tid' "$PANE_MAP" > "$tmp"
    mv "$tmp" "$PANE_MAP"
}

panes_in_tab() {
    _tab_id="$1"
    if [ -z "$_tab_id" ]; then
        echo "Usage: panes_in_tab <tab_id>" >&2
        return 1
    fi
    awk -v tid="$_tab_id" '$3 == tid {print $1}' "$PANE_MAP"
}

tab_for_pane() {
    _tmux_id="$1"
    if [ -z "$_tmux_id" ]; then
        echo "Usage: tab_for_pane <tmux_id>" >&2
        return 1
    fi
    result=$(awk -v tid="$_tmux_id" '$1 == tid {print $3; exit}' "$PANE_MAP")
    if [ -z "$result" ]; then
        return 1
    fi
    echo "$result"
}
PANE_MAP_EOF

cat > "$INSTALL_DIR/bin/tmux" << 'TMUX_SHIM_EOF'
#!/bin/sh
set -eu

# Guard / Passthrough - exit early if not in shim context
if [ "${TERM_PROGRAM:-}" != "WezTerm" ] || [ -z "${WEZTERM_SHIM_LIB:-}" ]; then
    real_tmux="${REAL_TMUX:-$(command -v tmux 2>/dev/null || true)}"
    if [ -n "$real_tmux" ]; then
        exec "$real_tmux" "$@"
    fi
    echo "tmux: command not found" >&2
    exit 127
fi

# Source the pane-map library
. "$WEZTERM_SHIM_LIB"

# Handler: version
handle_version() {
    echo "tmux 3.4"
}

# Handler: display-message
handle_display_message() {
    target=""
    format=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -t) target="$2"; shift 2 ;;
            -p) format="$2"; shift 2 ;;
            *)  shift ;;
        esac
    done
    case "$format" in
        *'#{pane_id}'*)
            if [ -n "$target" ]; then
                echo "$target"
            else
                echo "${TMUX_PANE:-}"
            fi
            return 0
            ;;
        *'#{session_name}:#{window_index}'*)
            _tab_id="${WEZTERM_SHIM_TAB:-0}"
            if [ -n "$target" ]; then
                _tab_id=$(tab_for_pane "$target")
            fi
            echo "wezterm:${_tab_id}"
            return 0
            ;;
    esac
    echo "$format"
}

# Handler: split-window
handle_split_window() {
    target="${TMUX_PANE:-}"
    direction="--bottom"
    size=""
    print_flag=false
    format="#{pane_id}"
    while [ $# -gt 0 ]; do
        case "$1" in
            -t) target="$2"; shift 2 ;;
            -h) direction="--right"; shift ;;
            -v) direction="--bottom"; shift ;;
            -l) size="$2"; shift 2 ;;
            -P) print_flag=true; shift ;;
            -F) format="$2"; shift 2 ;;
            *)  shift ;;
        esac
    done
    wez_pane=$(wez_from_tmux "$target")
    split_args="$direction --pane-id $wez_pane"
    if [ -n "$size" ]; then
        percent="${size%%%}"
        split_args="$split_args --percent $percent"
    fi
    new_wez_pane=$(wezterm cli split-pane $split_args)
    _tab_id=$(tab_for_pane "$target")
    new_tmux_id=$(alloc_pane_id "$new_wez_pane" "$_tab_id")
    if [ "$print_flag" = true ]; then
        echo "$new_tmux_id"
    fi
}

# Handler: send-keys
handle_send_keys() {
    target="${TMUX_PANE:-}"
    cmd=""
    has_enter=false
    while [ $# -gt 0 ]; do
        case "$1" in
            -t) target="$2"; shift 2 ;;
            Enter|C-m)
                has_enter=true
                shift
                ;;
            *)
                if [ -n "$cmd" ]; then
                    cmd="$cmd $1"
                else
                    cmd="$1"
                fi
                shift
                ;;
        esac
    done
    wez_pane=$(wez_from_tmux "$target")
    if [ "$has_enter" = true ]; then
        printf '%s\n' "$cmd" | wezterm cli send-text --no-paste --pane-id "$wez_pane"
    else
        printf '%s' "$cmd" | wezterm cli send-text --no-paste --pane-id "$wez_pane"
    fi
}

# Handler: list-panes
handle_list_panes() {
    target="${WEZTERM_SHIM_TAB:-0}"
    format="#{pane_id}"
    while [ $# -gt 0 ]; do
        case "$1" in
            -t) target="$2"; shift 2 ;;
            -F) format="$2"; shift 2 ;;
            *)  shift ;;
        esac
    done
    case "$target" in
        %*)  _tab_id=$(tab_for_pane "$target") ;;
        wezterm:*) _tab_id="${target#wezterm:}" ;;
        *)   _tab_id="$target" ;;
    esac
    panes=$(panes_in_tab "$_tab_id")
    if [ -n "$panes" ]; then
        echo "$panes"
    fi
}

# Handler: select-pane
handle_select_pane() {
    target="${TMUX_PANE:-}"
    has_style=false
    while [ $# -gt 0 ]; do
        case "$1" in
            -t) target="$2"; shift 2 ;;
            -P|-T) has_style=true; shift 2 ;;
            *)  shift ;;
        esac
    done
    if [ "$has_style" = true ]; then
        exit 0
    fi
    wez_pane=$(wez_from_tmux "$target")
    wezterm cli activate-pane --pane-id "$wez_pane" >/dev/null 2>&1
}

# Handler: kill-pane
handle_kill_pane() {
    target="${TMUX_PANE:-}"
    while [ $# -gt 0 ]; do
        case "$1" in
            -t) target="$2"; shift 2 ;;
            *)  shift ;;
        esac
    done
    wez_pane=$(wez_from_tmux "$target")
    wezterm cli kill-pane --pane-id "$wez_pane" >/dev/null 2>&1
    remove_pane "$target"
}

# Dispatch
cmd="${1:-}"
shift || true

case "$cmd" in
    -V)
        handle_version
        ;;
    display-message)
        handle_display_message "$@"
        ;;
    split-window)
        handle_split_window "$@"
        ;;
    send-keys)
        handle_send_keys "$@"
        ;;
    list-panes)
        handle_list_panes "$@"
        ;;
    select-pane)
        handle_select_pane "$@"
        ;;
    kill-pane)
        handle_kill_pane "$@"
        ;;
    select-layout|resize-pane|set-option|set-window-option|\
    has-session|new-session|new-window|list-sessions|list-windows|\
    break-pane|join-pane|move-window|swap-pane)
        exit 0
        ;;
    *)
        if [ -n "${REAL_TMUX:-}" ]; then
            exec "$REAL_TMUX" "$cmd" "$@"
        fi
        echo "wezcld: unhandled command: $cmd" >&2
        exit 1
        ;;
esac
TMUX_SHIM_EOF

cat > "$INSTALL_DIR/bin/wezcld" << 'WEZCLD_EOF'
#!/bin/sh
set -eu

# Detect WezTerm
if [ "${TERM_PROGRAM:-}" != "WezTerm" ]; then
    echo "Warning: Not running in WezTerm. Falling back to plain claude." >&2
    exec claude "$@"
fi

# Resolve paths (follow symlinks) — POSIX compatible
SOURCE="$0"
while [ -L "$SOURCE" ]; do
    DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    case "$SOURCE" in
        /*) ;;
        *)  SOURCE="$DIR/$SOURCE" ;;
    esac
done
SHIM_DIR="$(cd "$(dirname "$SOURCE")/.." && pwd)"

# Find real tmux binary (not our shim)
REAL_TMUX=""
saved_ifs="$IFS"
IFS=:
for path_entry in $PATH; do
    IFS="$saved_ifs"
    if [ "$path_entry" = "$SHIM_DIR/bin" ]; then
        continue
    fi
    if [ -x "$path_entry/tmux" ]; then
        REAL_TMUX="$path_entry/tmux"
        break
    fi
done
IFS="$saved_ifs"

# Source pane-map library
. "$SHIM_DIR/lib/pane-map.sh"

# Initialize shim state
shim_init

# Get current WezTerm pane and tab info
wez_pane_id="${WEZTERM_PANE:-}"
if [ -z "$wez_pane_id" ]; then
    wez_pane_id=$(wezterm cli list --format json | jq -r '.[] | select(.is_active) | .pane_id' | head -1)
fi

if [ -z "$wez_pane_id" ]; then
    echo "Error: Could not determine WezTerm pane ID" >&2
    exit 1
fi

# Get tab ID for this pane
tab_id=$(wezterm cli list --format json | jq -r ".[] | select(.pane_id == $wez_pane_id) | .tab_id" | head -1)

if [ -z "$tab_id" ]; then
    echo "Error: Could not determine WezTerm tab ID" >&2
    exit 1
fi

# Allocate leader pane ID for Claude
leader_pane=$(alloc_pane_id "$wez_pane_id" "$tab_id")

# Export fake tmux environment
export TMUX="/fake/wezcld,0,0"
export TMUX_PANE="$leader_pane"
export WEZTERM_SHIM_LIB="$SHIM_DIR/lib/pane-map.sh"
export WEZTERM_SHIM_TAB="$tab_id"
export WEZTERM_SHIM_DIR="$SHIM_DIR"
export REAL_TMUX="${REAL_TMUX:-}"
export PATH="$SHIM_DIR/bin:$PATH"

# Launch Claude Code in the fake tmux environment
exec claude "$@"
WEZCLD_EOF

# Make scripts executable
chmod +x "$INSTALL_DIR/bin/wezcld" "$INSTALL_DIR/bin/tmux" "$INSTALL_DIR/lib/pane-map.sh"

# Remove old symlinks/files before creating wrappers
rm -f "$BIN_DIR/wezcld" "$BIN_DIR/tmux"

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
