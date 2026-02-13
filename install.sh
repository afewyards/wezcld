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
cat > "$INSTALL_DIR/bin/it2" << 'IT2_SHIM_EOF'
#!/bin/sh
# it2 - iTerm2 CLI shim for wezcld
# Logs all invocations and returns fake responses for observation mode

set -eu

# Determine state directory
STATE_DIR="${WEZCLD_STATE:-$HOME/.local/state/wezcld}"
mkdir -p "$STATE_DIR"

LOG_FILE="$STATE_DIR/it2-calls.log"
COUNTER_DIR="$STATE_DIR/it2-counter"

# Atomic counter for fake session IDs
get_next_session_id() {
    # Use mkdir as atomic lock
    lock_acquired=0
    counter=0

    # Detect and remove stale lock
    if [ -d "$COUNTER_DIR.lock" ]; then
        lock_pid=$(cat "$COUNTER_DIR.lock/pid" 2>/dev/null || echo "")
        if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
            rmdir "$COUNTER_DIR.lock" 2>/dev/null || true
        fi
    fi

    for _ in 1 2 3; do
        if mkdir "$COUNTER_DIR.lock" 2>/dev/null; then
            lock_acquired=1
            echo "$$" > "$COUNTER_DIR.lock/pid"
            break
        fi
        sleep 1
    done

    if [ "$lock_acquired" = 0 ]; then
        # Fallback if lock fails after 3 retries
        echo "0"
        return
    fi

    # Read current counter
    if [ -f "$COUNTER_DIR" ]; then
        counter=$(cat "$COUNTER_DIR")
    else
        counter=0
    fi

    # Increment and write back
    counter=$((counter + 1))
    echo "$counter" > "$COUNTER_DIR"

    # Release lock
    rm -f "$COUNTER_DIR.lock/pid"
    rmdir "$COUNTER_DIR.lock"

    echo "$counter"
}

# Log invocation with ISO timestamp
log_call() {
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    exit_code="$1"
    shift
    output="$*"

    printf '[%s] ARGV: %s | EXIT: %d | STDOUT: %s\n' \
        "$timestamp" "$ARGV_STR" "$exit_code" "$output" >> "$LOG_FILE"
}

# Grid-panes file locking (mkdir-based atomic lock)
grid_lock() {
    lock_dir="$STATE_DIR/grid-panes.lock"
    # Detect and remove stale lock
    if [ -d "$lock_dir" ]; then
        lock_pid=$(cat "$lock_dir/pid" 2>/dev/null || echo "")
        if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
            rm -f "$lock_dir/pid"
            rmdir "$lock_dir" 2>/dev/null || true
        fi
    fi
    for _ in 1 2 3 4 5; do
        if mkdir "$lock_dir" 2>/dev/null; then
            echo "$$" > "$lock_dir/pid"
            return 0
        fi
        sleep 0.2
    done
    return 1
}

grid_unlock() {
    rm -f "$STATE_DIR/grid-panes.lock/pid"
    rmdir "$STATE_DIR/grid-panes.lock" 2>/dev/null || true
}

# Remove pane IDs from grid-panes that no longer exist in WezTerm
prune_stale_panes() {
    grid_file="$STATE_DIR/grid-panes"
    [ -f "$grid_file" ] || return 0
    [ -s "$grid_file" ] || return 0

    # Get live pane IDs; skip pruning if wezterm cli fails
    live_output=$(wezterm cli list 2>/dev/null) || return 0
    live_panes=$(printf '%s\n' "$live_output" | awk 'NR>1 {print $3}')

    tmp="$grid_file.prune.$$"
    : > "$tmp"
    while IFS= read -r pane_id; do
        [ -n "$pane_id" ] || continue
        if printf '%s\n' "$live_panes" | grep -qx "$pane_id"; then
            printf '%s\n' "$pane_id" >> "$tmp"
        fi
    done < "$grid_file"
    mv "$tmp" "$grid_file"
}

# Store original arguments for logging
ARGV_STR="it2"
for arg in "$@"; do
    # Sanitize: replace newlines with spaces, wrap args with special chars in single quotes
    sanitized=$(printf '%s' "$arg" | tr '\n' ' ')
    case "$sanitized" in
        *[\ \"\|]*) ARGV_STR="$ARGV_STR '${sanitized}'" ;;
        *) ARGV_STR="$ARGV_STR $sanitized" ;;
    esac
done

# Dispatch based on arguments
main() {
    exit_code=0  # Always 0 for Phase 1 — all commands fake success
    output=""

    case "${1:-}" in
        --version)
            output="it2 0.2.3"
            echo "$output"
            ;;
        --help|"")
            output="it2 - iTerm2 CLI (wezcld shim)"
            echo "$output"
            ;;
        app)
            case "${2:-}" in
                version)
                    output="it2 0.2.3"
                    echo "$output"
                    ;;
                *)
                    output=""
                    ;;
            esac
            ;;
        session)
            case "${2:-}" in
                split)
                    # Parse -v flag and -s <parent> flag (parse for logging, but ignore -s for grid)
                    shift 2  # skip "session" and "split"
                    parent=""
                    while [ $# -gt 0 ]; do
                        case "$1" in
                            -v|--vertical)
                                # -v means vertical split
                                shift
                                ;;
                            -s|--session)
                                parent="$2"
                                shift 2
                                ;;
                            *)
                                shift
                                ;;
                        esac
                    done

                    # Grid layout algorithm (under lock)
                    grid_lock || { echo "Failed to acquire grid lock" >&2; exit 1; }

                    # Prune stale panes before calculating positions
                    prune_stale_panes

                    MAX_COLS=3
                    GRID_FILE="$STATE_DIR/grid-panes"

                    # Count existing panes
                    agent_count=0
                    if [ -f "$GRID_FILE" ]; then
                        agent_count=$(wc -l < "$GRID_FILE" 2>/dev/null | tr -d ' ')
                    fi

                    # Calculate grid position
                    row=$((agent_count / MAX_COLS))
                    col=$((agent_count % MAX_COLS))

                    # Determine split direction and target pane
                    new_pane_id=""
                    if [ "$row" -eq 0 ] && [ "$col" -eq 0 ]; then
                        # First agent: split from leader (top)
                        new_pane_id=$(wezterm cli split-pane --top --percent 60) || true
                    elif [ "$row" -eq 0 ]; then
                        # Filling first row: split right from previous pane
                        previous_pane=$(tail -n 1 "$GRID_FILE")
                        # Calculate percent so all columns end up equal width
                        remaining=$((MAX_COLS - col))
                        pct=$(( (100 * remaining + (remaining + 1) / 2) / (remaining + 1) ))
                        new_pane_id=$(wezterm cli split-pane --right --percent "$pct" --pane-id "$previous_pane") || true
                    else
                        # New row: split bottom from pane above (same column)
                        pane_above_index=$((agent_count - MAX_COLS + 1))
                        pane_above=$(sed -n "${pane_above_index}p" "$GRID_FILE")
                        new_pane_id=$(wezterm cli split-pane --bottom --pane-id "$pane_above") || true
                    fi

                    if [ -z "$new_pane_id" ]; then
                        grid_unlock
                        echo "Failed to create split pane" >&2
                        exit 1
                    fi

                    # Append to grid-panes file
                    echo "$new_pane_id" >> "$GRID_FILE"

                    grid_unlock

                    # Refocus leader pane
                    wezterm cli activate-pane --pane-id "${WEZTERM_PANE:-0}" 2>/dev/null || true

                    output="Created new pane: $new_pane_id"
                    echo "$output"
                    ;;
                send|send-text)
                    output=""
                    ;;
                run)
                    # Parse -s <id> flag and command
                    shift 2  # skip "session" and "run"
                    target=""
                    cmd=""
                    while [ $# -gt 0 ]; do
                        case "$1" in
                            -s|--session)
                                target="$2"
                                shift 2
                                ;;
                            *)
                                if [ -z "$cmd" ]; then
                                    cmd="$1"
                                else
                                    cmd="$cmd $1"
                                fi
                                shift
                                ;;
                        esac
                    done

                    # Send command to target pane
                    if [ -n "$target" ] && [ -n "$cmd" ]; then
                        printf '%s\n' "$cmd" | wezterm cli send-text --no-paste --pane-id "$target"
                    fi
                    output=""
                    ;;
                close)
                    shift 2  # skip "session" and "close"
                    target=""
                    while [ $# -gt 0 ]; do
                        case "$1" in
                            -s|--session) target="$2"; shift 2 ;;
                            --force|-f) shift ;;
                            *) shift ;;
                        esac
                    done
                    if [ -n "$target" ]; then
                        wezterm cli kill-pane --pane-id "$target" 2>/dev/null || true
                        # Remove from grid-panes (under lock)
                        if grid_lock; then
                            if [ -f "$STATE_DIR/grid-panes" ]; then
                                tmp="$STATE_DIR/grid-panes.tmp"
                                grep -v "^${target}$" "$STATE_DIR/grid-panes" > "$tmp" 2>/dev/null || true
                                mv "$tmp" "$STATE_DIR/grid-panes"
                            fi
                            grid_unlock
                        fi
                    fi
                    output="Session closed"
                    echo "$output"
                    ;;
                list)
                    output="Session ID       Name    Title           Size    TTY"
                    echo "$output"
                    ;;
                focus|clear|restart)
                    output=""
                    ;;
                *)
                    output=""
                    ;;
            esac
            ;;
        split)
            session_id=$(get_next_session_id)
            output="Created new pane: fake-session-$session_id"
            echo "$output"
            ;;
        send|run)
            output=""
            ;;
        vsplit)
            session_id=$(get_next_session_id)
            output="Created new pane: fake-session-$session_id"
            echo "$output"
            ;;
        ls)
            output="Session ID       Name    Title           Size    TTY"
            echo "$output"
            ;;
        *)
            output=""
            ;;
    esac

    log_call "$exit_code" "$output"
    return "$exit_code"
}

main "$@"
IT2_SHIM_EOF

cat > "$INSTALL_DIR/bin/wezcld" << 'WEZCLD_EOF'
#!/bin/sh
set -eu

# Uninstall
if [ "${1:-}" = "--uninstall" ]; then
    BIN_DIR="$HOME/.local/bin"
    INSTALL_DIR="$HOME/.local/share/wezcld"
    STATE_DIR="$HOME/.local/state/wezcld"
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
    echo "wezcld uninstalled."
    exit 0
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

# Version
if [ "${1:-}" = "--version" ] || [ "${1:-}" = "-v" ]; then
    VER="dev"
    [ -f "$SHIM_DIR/VERSION" ] && VER="$(cat "$SHIM_DIR/VERSION")"
    echo "wezcld $VER"
    exit 0
fi

# Detect WezTerm
if [ "${TERM_PROGRAM:-}" != "WezTerm" ]; then
    echo "Warning: Not running in WezTerm. Falling back to plain claude." >&2
    exec claude "$@"
fi

# Initialize state directory
STATE_DIR="${WEZCLD_STATE:-$HOME/.local/state/wezcld}"
mkdir -p "$STATE_DIR"

# Override TERM_PROGRAM to trigger Claude Code's iTerm detection
export TERM_PROGRAM="iTerm.app"
export LC_TERMINAL="iTerm2"
export ITERM_SESSION_ID="wezcld-$$"

# Put our it2 shim first in PATH
export WEZCLD_STATE="$STATE_DIR"
export PATH="$SHIM_DIR/bin:$PATH"

# Launch Claude Code with iTerm teammate mode
exec claude --teammate-mode tmux "$@"
WEZCLD_EOF

cat > "$INSTALL_DIR/VERSION" << 'VERSION_EOF'
0.1.0
VERSION_EOF

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
