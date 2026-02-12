# WezTerm tmux Shim — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fake `tmux` script + launcher that lets Claude Code agent teams use WezTerm split panes instead of tmux.

**Architecture:** Two components: (1) a `claude-wez` wrapper that sets `$TMUX`/`$TMUX_PANE` env vars to trick Claude Code into native tmux mode, and (2) a `tmux` shim script placed before real tmux in PATH that translates tmux subcommands to `wezterm cli` equivalents. A pane mapping file (`%N` ↔ WezTerm integer IDs) bridges the ID format gap. Requires `jq` for JSON parsing.

**Tech Stack:** Bash, jq, WezTerm CLI (`wezterm cli`), Claude Code agent teams

**Key insight:** By faking `$TMUX`, Claude Code uses its "inside tmux" code path — no need to handle the external `-L socket` mode. Only the leader process needs the shim; teammates are plain `claude` processes launched via `send-text` into WezTerm panes.

---

## Project structure

```
wezterm-tmux-shim/
├── bin/
│   ├── tmux              # The shim (intercepts tmux calls → wezterm cli)
│   └── claude-wez        # Wrapper to launch claude with fake $TMUX env
├── lib/
│   └── pane-map.sh       # Pane ID mapping utilities (sourced by shim)
├── install.sh            # Symlinks bin/ into ~/.local/bin
└── docs/plans/
```

Runtime state at `~/.local/state/wezterm-tmux-shim/`:
```
pane-map      # Persistent map: %0=199\n%1=203\n...
counter       # Next %N integer (atomically incremented)
counter.lock  # flock target
```

---

## tmux commands Claude Code uses (inside-tmux path)

| Command | Frequency | Shim action |
|---------|-----------|-------------|
| `-V` | Once at startup | Echo fake version string |
| `display-message -p "#{pane_id}"` | Rare (fallback) | Return `$TMUX_PANE` |
| `display-message -t %N -p "#{session_name}:#{window_index}"` | Once per session | Return `wezterm:<tab_id>` |
| `split-window -t %N -h [-l 70%] -P -F "#{pane_id}"` | Per teammate | `wezterm cli split-pane --right [--percent N] --pane-id <wez_id>` |
| `split-window -t %N -v -P -F "#{pane_id}"` | Per teammate | `wezterm cli split-pane --bottom --pane-id <wez_id>` |
| `send-keys -t %N <cmd> Enter` | Per teammate | `printf '%s\n' "$cmd" \| wezterm cli send-text --no-paste --pane-id <wez_id>` |
| `list-panes -t <target> -F "#{pane_id}"` | Rebalancing | `wezterm cli list --format json` filtered by tab_id, output mapped `%N` IDs |
| `select-layout -t <target> main-vertical\|tiled` | Rebalancing | No-op (WezTerm has no layout engine) |
| `resize-pane -t %N -x 30%` | After layout | No-op (skip; WezTerm splits are already 50/50 or as specified) |
| `select-pane -t %N -P bg=default,fg=<color>` | Styling | No-op |
| `select-pane -t %N -T <name>` | Naming | `wezterm cli set-tab-title` (best-effort, pane titles not directly supported) |
| `set-option -p -t %N ...` | Border styling | No-op |
| `set-option -w -t <window> pane-border-status top` | Enable borders | No-op |
| `kill-pane -t %N` | Cleanup | `wezterm cli kill-pane --pane-id <wez_id>` |
| `has-session -t <name>` | External mode only | Exit 0 (shouldn't be reached) |

---

### Task 1: Pane mapping utilities

**Files:**
- Create: `lib/pane-map.sh`

**Step 1: Write `lib/pane-map.sh`**

```bash
#!/usr/bin/env bash
# Pane ID mapping: tmux %N <-> WezTerm integer IDs
# Sourced by the shim and wrapper.

SHIM_STATE_DIR="$HOME/.local/state/wezterm-tmux-shim"
PANE_MAP_FILE="$SHIM_STATE_DIR/pane-map"
COUNTER_FILE="$SHIM_STATE_DIR/counter"
LOCK_FILE="$SHIM_STATE_DIR/counter.lock"

shim_init() {
    mkdir -p "$SHIM_STATE_DIR"
    [ -f "$COUNTER_FILE" ] || echo "0" > "$COUNTER_FILE"
    [ -f "$PANE_MAP_FILE" ] || touch "$PANE_MAP_FILE"
}

# Allocate next %N, map it to a WezTerm pane ID, print the %N.
# Usage: alloc_pane_id <wezterm_pane_id>
alloc_pane_id() {
    local wez_id="$1" tmux_id
    (
        flock -x 200
        local n
        n=$(cat "$COUNTER_FILE")
        tmux_id="%${n}"
        echo "$((n + 1))" > "$COUNTER_FILE"
        echo "${tmux_id}=${wez_id}" >> "$PANE_MAP_FILE"
        echo "$tmux_id"
    ) 200>"$LOCK_FILE"
}

# Lookup WezTerm ID from tmux %N.  Usage: wez_from_tmux "%3"
wez_from_tmux() {
    local tmux_id="$1"
    sed -n "s/^${tmux_id}=//p" "$PANE_MAP_FILE" | tail -1
}

# Lookup tmux %N from WezTerm ID.  Usage: tmux_from_wez "203"
tmux_from_wez() {
    local wez_id="$1"
    grep "=${wez_id}$" "$PANE_MAP_FILE" | tail -1 | cut -d= -f1
}

# Remove a mapping.  Usage: remove_pane "%3"
remove_pane() {
    local tmux_id="$1"
    local tmp="$PANE_MAP_FILE.tmp"
    grep -v "^${tmux_id}=" "$PANE_MAP_FILE" > "$tmp" && mv "$tmp" "$PANE_MAP_FILE"
}

# Get all tmux pane IDs mapped to panes in a given WezTerm tab.
# Usage: panes_in_tab <tab_id>
panes_in_tab() {
    local tab_id="$1"
    local wez_panes
    wez_panes=$(wezterm cli list --format json | jq -r ".[] | select(.tab_id == ${tab_id}) | .pane_id")
    for wez_id in $wez_panes; do
        tmux_from_wez "$wez_id"
    done
}

# Get the tab_id for a WezTerm pane.  Usage: tab_for_pane <wezterm_pane_id>
tab_for_pane() {
    local wez_id="$1"
    wezterm cli list --format json | jq -r ".[] | select(.pane_id == ${wez_id}) | .tab_id"
}
```

**Step 2: Commit**

```
feat: add pane ID mapping utilities
```

---

### Task 2: Wrapper script (`claude-wez`)

**Files:**
- Create: `bin/claude-wez`

**Step 1: Write `bin/claude-wez`**

```bash
#!/usr/bin/env bash
# Launch Claude Code with WezTerm tmux shim enabled.
# Usage: claude-wez [claude args...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"

# Only works inside WezTerm
if [ "$TERM_PROGRAM" != "WezTerm" ]; then
    echo "claude-wez: not running inside WezTerm, launching claude directly" >&2
    exec claude "$@"
fi

# shellcheck source=../lib/pane-map.sh
source "$LIB_DIR/pane-map.sh"
shim_init

# Register leader pane: map current $WEZTERM_PANE to a %N
LEADER_TMUX_PANE=$(alloc_pane_id "$WEZTERM_PANE")

# Cache leader's tab ID for list-panes
LEADER_TAB_ID=$(tab_for_pane "$WEZTERM_PANE")

# Fake tmux environment — only for this process tree
export TMUX="/fake/wezterm-tmux-shim"
export TMUX_PANE="$LEADER_TMUX_PANE"
export WEZTERM_SHIM_TAB="$LEADER_TAB_ID"
export WEZTERM_SHIM_LIB="$LIB_DIR"

# Put shim's bin/ first in PATH so `tmux` resolves to our shim
export PATH="$SCRIPT_DIR:$PATH"

exec claude "$@"
```

**Step 2: Make executable**

```bash
chmod +x bin/claude-wez
```

**Step 3: Commit**

```
feat: add claude-wez launcher wrapper
```

---

### Task 3: Shim core — version, display-message, split-window

**Files:**
- Create: `bin/tmux`

**Step 1: Write the shim skeleton + `-V`, `display-message`, `split-window`**

```bash
#!/usr/bin/env bash
# WezTerm tmux shim — intercepts tmux commands from Claude Code,
# translates to wezterm cli equivalents.

set -euo pipefail

REAL_TMUX="${REAL_TMUX:-/opt/homebrew/bin/tmux}"

# Pass through to real tmux if not in WezTerm or not shimmed
if [ "$TERM_PROGRAM" != "WezTerm" ] || [ -z "${WEZTERM_SHIM_LIB:-}" ]; then
    exec "$REAL_TMUX" "$@"
fi

# shellcheck source=../lib/pane-map.sh
source "$WEZTERM_SHIM_LIB/pane-map.sh"

# --- Handlers ---

handle_version() {
    echo "tmux 3.5a (wezterm-shim)"
}

handle_display_message() {
    # Parse: [-t %N] -p "<format>"
    local target="" format=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -t) target="$2"; shift 2 ;;
            -p) format="$2"; shift 2 ;;
            *)  shift ;;
        esac
    done

    case "$format" in
        '#{pane_id}')
            if [ -n "$target" ]; then
                echo "$target"
            else
                echo "$TMUX_PANE"
            fi
            ;;
        '#{session_name}:#{window_index}')
            local wez_id tab_id
            if [ -n "$target" ]; then
                wez_id=$(wez_from_tmux "$target")
                tab_id=$(tab_for_pane "$wez_id")
            else
                tab_id="${WEZTERM_SHIM_TAB}"
            fi
            echo "wezterm:${tab_id}"
            ;;
        *)
            echo "wezterm-shim: unknown format: $format" >&2
            ;;
    esac
}

handle_split_window() {
    # Parse: -t %N [-h|-v] [-l <size>] -P -F "#{pane_id}"
    local target="" direction="--right" percent=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -t) target="$2"; shift 2 ;;
            -h) direction="--right"; shift ;;
            -v) direction="--bottom"; shift ;;
            -l) percent="${2%\%}"; shift 2 ;;  # strip trailing %
            -P|-F) shift ;; # -F takes an arg
            '#{pane_id}') shift ;;  # format string arg to -F
            --) shift; break ;;     # remaining = command (unused, send-keys handles it)
            *)  shift ;;
        esac
    done

    # Resolve target to WezTerm pane ID
    local wez_target
    if [ -n "$target" ]; then
        wez_target=$(wez_from_tmux "$target")
    else
        wez_target="$WEZTERM_PANE"
    fi

    # Build wezterm cli split-pane command
    local cmd=(wezterm cli split-pane "$direction" --pane-id "$wez_target")
    if [ -n "$percent" ]; then
        cmd+=(--percent "$percent")
    fi

    # Execute and capture new pane ID (wezterm prints integer on stdout)
    local new_wez_id
    new_wez_id=$("${cmd[@]}")

    # Allocate tmux %N and record mapping
    local new_tmux_id
    new_tmux_id=$(alloc_pane_id "$new_wez_id")

    # Claude Code expects the pane ID on stdout (via -P -F "#{pane_id}")
    echo "$new_tmux_id"
}

# --- Dispatch ---

case "${1:-}" in
    -V)              handle_version ;;
    display-message) shift; handle_display_message "$@" ;;
    split-window)    shift; handle_split_window "$@" ;;
    *)               echo "wezterm-shim: not yet handled: tmux $*" >&2; exit 0 ;;
esac
```

**Step 2: Make executable**

```bash
chmod +x bin/tmux
```

**Step 3: Commit**

```
feat: shim core — version, display-message, split-window
```

---

### Task 4: Shim — send-keys + list-panes

**Files:**
- Modify: `bin/tmux`

**Step 1: Add `handle_send_keys` after `handle_split_window`**

```bash
handle_send_keys() {
    # Parse: -t %N <command_text...> Enter
    # Claude Code calls: send-keys -t %3 "cd /path && claude ..." Enter
    local target="" args=()
    while [ $# -gt 0 ]; do
        case "$1" in
            -t) target="$2"; shift 2 ;;
            *)  args+=("$1"); shift ;;
        esac
    done

    # Last arg is "Enter" (or "C-m") — the keypress to execute the command
    # Remove it; we'll append \n instead
    local last="${args[-1]:-}"
    if [ "$last" = "Enter" ] || [ "$last" = "C-m" ]; then
        unset 'args[-1]'
    fi

    # Join remaining args as the command string
    local cmd_text="${args[*]}"

    # Resolve target
    local wez_target
    wez_target=$(wez_from_tmux "$target")

    # Send command + newline to the pane
    printf '%s\n' "$cmd_text" | wezterm cli send-text --no-paste --pane-id "$wez_target"
}

handle_list_panes() {
    # Parse: -t <target> -F "#{pane_id}"
    # <target> = "session:window" e.g. "wezterm:56"
    local target="" format=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -t) target="$2"; shift 2 ;;
            -F) format="$2"; shift 2 ;;
            -a) shift ;;  # "all" flag, treat same
            *)  shift ;;
        esac
    done

    # Extract tab_id from target (format: "wezterm:<tab_id>")
    local tab_id
    tab_id="${target##*:}"

    # Get all pane IDs in this tab and output their tmux %N equivalents
    panes_in_tab "$tab_id"
}
```

**Step 2: Add to dispatch case statement**

```bash
    send-keys)       shift; handle_send_keys "$@" ;;
    list-panes)      shift; handle_list_panes "$@" ;;
```

**Step 3: Commit**

```
feat: shim send-keys and list-panes handlers
```

---

### Task 5: Shim — select-pane, kill-pane, no-ops

**Files:**
- Modify: `bin/tmux`

**Step 1: Add remaining handlers**

```bash
handle_select_pane() {
    # Parse: -t %N [-P bg=...,fg=...] [-T <name>]
    local target="" title="" styling=false
    while [ $# -gt 0 ]; do
        case "$1" in
            -t) target="$2"; shift 2 ;;
            -T) title="$2"; shift 2 ;;
            -P) styling=true; shift ;; # followed by color spec, skip it
            bg=*|fg=*|bg=*,fg=*) shift ;;  # color specs, no-op
            *)  shift ;;
        esac
    done

    local wez_target
    wez_target=$(wez_from_tmux "$target")

    # Focus the pane (only if no styling/title flags — pure focus request)
    if [ "$styling" = false ] && [ -z "$title" ]; then
        wezterm cli activate-pane --pane-id "$wez_target"
    fi

    # Title: best-effort, set pane title via CLI if available
    # WezTerm doesn't have per-pane titles via CLI, skip.
}

handle_kill_pane() {
    # Parse: -t %N
    local target=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -t) target="$2"; shift 2 ;;
            *)  shift ;;
        esac
    done

    local wez_target
    wez_target=$(wez_from_tmux "$target")

    wezterm cli kill-pane --pane-id "$wez_target" 2>/dev/null || true
    remove_pane "$target"
}
```

**Step 2: Update dispatch with all remaining subcommands**

```bash
    select-pane)     shift; handle_select_pane "$@" ;;
    kill-pane)       shift; handle_kill_pane "$@" ;;
    # Layout/styling — no-ops (WezTerm has no layout engine or dynamic pane borders)
    select-layout)   exit 0 ;;
    resize-pane)     exit 0 ;;
    set-option)      exit 0 ;;
    # Session management — not reached in inside-tmux mode, safe no-ops
    has-session)     exit 0 ;;
    new-session)     exit 0 ;;
    new-window)      exit 0 ;;
    list-windows)    exit 0 ;;
    list-sessions)   exit 0 ;;
    break-pane)      exit 0 ;;
    join-pane)       exit 0 ;;
```

**Step 3: Commit**

```
feat: shim select-pane, kill-pane, and no-op handlers
```

---

### Task 6: Install script + cleanup hook

**Files:**
- Create: `install.sh`

**Step 1: Write `install.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$(cd "$(dirname "$0")/bin" && pwd)"
TARGET="$HOME/.local/bin"

mkdir -p "$TARGET"

# Detect real tmux location
REAL_TMUX=$(command -v tmux 2>/dev/null || echo "/opt/homebrew/bin/tmux")

# Symlink claude-wez
ln -sf "$BIN_DIR/claude-wez" "$TARGET/claude-wez"

# Symlink shim as tmux — ONLY if ~/.local/bin is in PATH before real tmux
# User must ensure PATH ordering: ~/.local/bin before /opt/homebrew/bin
ln -sf "$BIN_DIR/tmux" "$TARGET/tmux"

echo "Installed:"
echo "  $TARGET/claude-wez -> $BIN_DIR/claude-wez"
echo "  $TARGET/tmux       -> $BIN_DIR/tmux (shim)"
echo ""
echo "Real tmux detected at: $REAL_TMUX"
echo "Set REAL_TMUX=$REAL_TMUX in your shell if different."
echo ""
echo "Usage: claude-wez          (instead of 'claude' for agent teams)"
echo ""
echo "IMPORTANT: Ensure ~/.local/bin is BEFORE $(dirname "$REAL_TMUX") in your PATH."
echo "Add to .zshrc:  export PATH=\"\$HOME/.local/bin:\$PATH\""
```

**Step 2: Make executable**

```bash
chmod +x install.sh
```

**Step 3: Commit**

```
feat: add install script
```

---

### Task 7: Manual integration test

**Not a code task — verification steps.**

1. Run `./install.sh`
2. Verify PATH: `which tmux` → `~/.local/bin/tmux`
3. Verify passthrough: open a regular terminal (not WezTerm), run `tmux -V` → real tmux
4. In WezTerm, run `claude-wez`
5. Verify `echo $TMUX` → `/fake/wezterm-tmux-shim`
6. Spawn a team with 2 agents
7. Verify: WezTerm splits into panes (not tmux panes)
8. Verify: teammates receive commands and start responding
9. After team shutdown, verify: `kill-pane` cleans up WezTerm panes

**Expected issues to watch for:**
- **Shell init race**: `send-text` fires before new pane's shell is ready → command not executed. Mitigation: add small `sleep 0.3` before `send-text` in `handle_split_window` or `handle_send_keys`.
- **`-F` arg parsing**: the format string `"#{pane_id}"` might be passed as a separate arg or joined with `-F`. Test both.
- **Real tmux still in PATH**: if `$PATH` ordering is wrong, the shim won't be called. `which tmux` must show `~/.local/bin/tmux`.

---

## Unresolved questions

1. **`-P` flag position**: Claude Code passes `-P -F "#{pane_id}"` to `split-window`. Does `-F` always follow `-P`, or can they be separate? Need to test with actual Claude Code invocation to confirm arg ordering.
2. **Concurrent split race**: Claude Code has a 200ms delay between spawns + a mutex. The shim's `alloc_pane_id` uses `flock`, but is there a race between `wezterm cli split-pane` returning and the pane's shell being ready for `send-text`?
3. **`select-pane -P` color arg**: Is the color spec the next positional arg (`-P "bg=default,fg=red"`) or a separate flag? Affects parsing.
4. **PATH safety**: Installing a `tmux` shim in `~/.local/bin` affects ALL tmux calls from that shell. The `TERM_PROGRAM` + `WEZTERM_SHIM_LIB` guard should prevent interference, but need to verify no edge cases (e.g., launching real tmux from within a claude-wez session).
5. **`jq` dependency**: Acceptable? Or should we use pure bash JSON parsing to avoid the dependency?
