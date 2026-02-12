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
