#!/usr/bin/env bash

# Bash library for mapping tmux-style pane IDs (%N) to WezTerm integer pane IDs

STATE_DIR="${WEZTERM_SHIM_STATE:-$HOME/.local/state/wezterm-tmux-shim}"
PANE_MAP="${STATE_DIR}/pane-map"
COUNTER="${STATE_DIR}/counter"
LOCK_DIR="${STATE_DIR}/counter.lock"
LOCK_TIMEOUT=50  # attempts (×0.1s = 5 seconds)

# Initialize state directory and files
shim_init() {
    mkdir -p "$STATE_DIR"

    if [[ ! -f "$COUNTER" ]]; then
        echo "0" > "$COUNTER"
    fi

    if [[ ! -f "$PANE_MAP" ]]; then
        touch "$PANE_MAP"
    fi
}

# Acquire lock with timeout
_acquire_lock() {
    local attempts=0
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        ((attempts++))
        if ((attempts >= LOCK_TIMEOUT)); then
            echo "Failed to acquire lock after ${LOCK_TIMEOUT} attempts" >&2
            return 1
        fi
        sleep 0.1
    done
    return 0
}

# Release lock
_release_lock() {
    rmdir "$LOCK_DIR" 2>/dev/null
}

# Allocate a new tmux-style pane ID and map it to WezTerm pane ID
# Usage: alloc_pane_id <wez_id> <tab_id>
# Prints: %N (the allocated tmux ID)
alloc_pane_id() {
    local wez_id="$1"
    local tab_id="$2"

    if [[ -z "$wez_id" || -z "$tab_id" ]]; then
        echo "Usage: alloc_pane_id <wez_id> <tab_id>" >&2
        return 1
    fi

    # Acquire lock
    if ! _acquire_lock; then
        return 1
    fi

    # Read current counter
    local counter
    counter=$(cat "$COUNTER" 2>/dev/null || echo "0")

    # Increment counter
    local next_id=$((counter + 1))
    echo "$next_id" > "$COUNTER"

    # Release lock
    _release_lock

    # Add mapping to pane-map
    local tmux_id="%${counter}"
    echo "$tmux_id $wez_id $tab_id" >> "$PANE_MAP"

    # Print allocated ID
    echo "$tmux_id"
}

# Look up WezTerm pane ID from tmux ID
# Usage: wez_from_tmux <tmux_id>
# Prints: wez_id
wez_from_tmux() {
    local tmux_id="$1"

    if [[ -z "$tmux_id" ]]; then
        echo "Usage: wez_from_tmux <tmux_id>" >&2
        return 1
    fi

    local result
    result=$(awk -v tid="$tmux_id" '$1 == tid {print $2; exit}' "$PANE_MAP")

    if [[ -z "$result" ]]; then
        return 1
    fi

    echo "$result"
}

# Look up tmux ID from WezTerm pane ID
# Usage: tmux_from_wez <wez_id>
# Prints: tmux_id
tmux_from_wez() {
    local wez_id="$1"

    if [[ -z "$wez_id" ]]; then
        echo "Usage: tmux_from_wez <wez_id>" >&2
        return 1
    fi

    local result
    result=$(awk -v wid="$wez_id" '$2 == wid {print $1; exit}' "$PANE_MAP")

    if [[ -z "$result" ]]; then
        return 1
    fi

    echo "$result"
}

# Remove a pane mapping
# Usage: remove_pane <tmux_id>
remove_pane() {
    local tmux_id="$1"

    if [[ -z "$tmux_id" ]]; then
        echo "Usage: remove_pane <tmux_id>" >&2
        return 1
    fi

    # Create temp file and filter out the line
    local tmp="${PANE_MAP}.tmp"
    awk -v tid="$tmux_id" '$1 != tid' "$PANE_MAP" > "$tmp"
    mv "$tmp" "$PANE_MAP"
}

# List all tmux pane IDs in a tab
# Usage: panes_in_tab <tab_id>
# Prints: one tmux_id per line
panes_in_tab() {
    local tab_id="$1"

    if [[ -z "$tab_id" ]]; then
        echo "Usage: panes_in_tab <tab_id>" >&2
        return 1
    fi

    awk -v tid="$tab_id" '$3 == tid {print $1}' "$PANE_MAP"
}

# Get tab ID for a pane
# Usage: tab_for_pane <tmux_id>
# Prints: tab_id
tab_for_pane() {
    local tmux_id="$1"

    if [[ -z "$tmux_id" ]]; then
        echo "Usage: tab_for_pane <tmux_id>" >&2
        return 1
    fi

    local result
    result=$(awk -v tid="$tmux_id" '$1 == tid {print $3; exit}' "$PANE_MAP")

    if [[ -z "$result" ]]; then
        return 1
    fi

    echo "$result"
}
