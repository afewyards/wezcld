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
                    # Parse -v flag and -s <parent> flag
                    shift 2  # skip "session" and "split"
                    split_args="--bottom"
                    parent=""
                    while [ $# -gt 0 ]; do
                        case "$1" in
                            -v|--vertical)
                                # -v means vertical split, keep --bottom
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

                    # Add parent pane ID if specified
                    if [ -n "$parent" ]; then
                        split_args="$split_args --pane-id $parent"
                    fi

                    # Call wezterm cli split-pane and get real pane ID
                    new_pane_id=$(wezterm cli split-pane $split_args)
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
