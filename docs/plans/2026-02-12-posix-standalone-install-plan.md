# POSIX Compatibility & Standalone Install — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make all wezcld scripts POSIX sh compatible and create a self-extracting installer with zero repo dependency.

**Architecture:** Convert bash-isms to POSIX sh across 3 source files + tests. Build script generates `install.sh` by embedding source files as heredocs. Installer copies to `~/.local/share/wezcld/`, creates thin wrappers in `~/.local/bin/`, auto-configures shell rc.

**Tech Stack:** POSIX sh, awk, jq (external dep kept)

---

### Task 1: POSIX-ify `lib/pane-map.sh`

**Files:**
- Modify: `lib/pane-map.sh`

Lowest-risk file — already mostly POSIX. Only bash-isms: `[[ ]]`, `local`, shebang.

**Step 1: Update shebang and replace bash-isms**

Change `#!/usr/bin/env bash` → `#!/bin/sh`. Replace all `[[ ... ]]` with `[ ... ]`. Replace `((attempts++))` and `((attempts >= N))` with POSIX arithmetic.

Full replacement:

```sh
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
```

Note: `local` is not POSIX but is supported by dash, ash, busybox sh, and every modern /bin/sh. We drop it to be safe and use underscore-prefixed names to avoid collisions.

**Step 2: Run tests to verify**

Run: `./tests/integration-test.sh`
Expected: Group 1 tests all pass (pane-map unit tests)

**Step 3: Commit**

```
feat(pane-map): convert to POSIX sh
```

---

### Task 2: POSIX-ify `bin/tmux`

**Files:**
- Modify: `bin/tmux`

Biggest rewrite. Key changes: arrays → positional params, `[[ ]]` → `[ ]`/`case`, `local` → function-scoped naming.

**Step 1: Rewrite bin/tmux in POSIX sh**

```sh
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
```

Key changes in `send-keys`: Instead of bash arrays, we build `cmd` as a space-delimited string and check for trailing `Enter`/`C-m` during the loop. This works because Claude Code sends commands as separate positional args.

**Step 2: Run tests to verify**

Run: `./tests/integration-test.sh`
Expected: Group 2 and 3 tests pass

**Step 3: Commit**

```
feat(tmux): convert shim to POSIX sh
```

---

### Task 3: POSIX-ify `bin/wezcld`

**Files:**
- Modify: `bin/wezcld`

Replace: symlink resolution loop, `type -a` with PATH scanning, `[[ ]]`.

**Step 1: Rewrite bin/wezcld in POSIX sh**

```sh
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
```

Key change: `type -a tmux` → POSIX `for path_entry in $PATH` loop with IFS splitting.

**Step 2: Run tests to verify**

Run: `./tests/integration-test.sh`
Expected: All tests pass

**Step 3: Commit**

```
feat(wezcld): convert launcher to POSIX sh
```

---

### Task 4: POSIX-ify `tests/integration-test.sh`

**Files:**
- Modify: `tests/integration-test.sh`

Replace: `BASH_SOURCE`, arrays, `(())` arithmetic, `[[ ]]`.

**Step 1: Rewrite tests in POSIX sh**

```sh
#!/bin/sh
set -eu

# Test framework
TESTS=0
PASSED=0
FAILED=0

pass() { TESTS=$((TESTS + 1)); PASSED=$((PASSED + 1)); echo "  + $1"; }
fail() { TESTS=$((TESTS + 1)); FAILED=$((FAILED + 1)); echo "  x $1: $2"; }

# Resolve script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SHIM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Setup temp state directory
WEZTERM_SHIM_STATE="$(mktemp -d)"
export WEZTERM_SHIM_STATE
trap 'rm -rf "$WEZTERM_SHIM_STATE"' EXIT

echo "Testing wezcld"
echo "=========================="
echo

# ============================================================================
# Group 1: pane-map.sh unit tests
# ============================================================================
echo "Group 1: pane-map.sh unit tests"
echo "--------------------------------"

. "$SHIM_DIR/lib/pane-map.sh"

# Test 1: shim_init creates state dir and files
shim_init
if [ -d "$WEZTERM_SHIM_STATE" ] && [ -f "$WEZTERM_SHIM_STATE/counter" ] && [ -f "$WEZTERM_SHIM_STATE/pane-map" ]; then
    pass "shim_init creates state dir, counter, and pane-map files"
else
    fail "shim_init creates state dir, counter, and pane-map files" "missing files"
fi

# Test 2: alloc_pane_id returns %0, then %1
id1=$(alloc_pane_id 42 5)
if [ "$id1" = "%0" ]; then
    pass "alloc_pane_id 42 5 returns %0"
else
    fail "alloc_pane_id 42 5 returns %0" "got '$id1'"
fi

id2=$(alloc_pane_id 43 5)
if [ "$id2" = "%1" ]; then
    pass "second alloc_pane_id returns %1"
else
    fail "second alloc_pane_id returns %1" "got '$id2'"
fi

# Test 3: wez_from_tmux %0 returns 42
wez_id=$(wez_from_tmux %0)
if [ "$wez_id" = "42" ]; then
    pass "wez_from_tmux %0 returns 42"
else
    fail "wez_from_tmux %0 returns 42" "got '$wez_id'"
fi

# Test 4: tmux_from_wez 42 returns %0
tmux_id=$(tmux_from_wez 42)
if [ "$tmux_id" = "%0" ]; then
    pass "tmux_from_wez 42 returns %0"
else
    fail "tmux_from_wez 42 returns %0" "got '$tmux_id'"
fi

# Test 5: tab_for_pane %0 returns 5
tab_id=$(tab_for_pane %0)
if [ "$tab_id" = "5" ]; then
    pass "tab_for_pane %0 returns 5"
else
    fail "tab_for_pane %0 returns 5" "got '$tab_id'"
fi

# Test 6: panes_in_tab 5 returns %0 and %1
panes=$(panes_in_tab 5)
expected=$(printf '%%0\n%%1')
if [ "$panes" = "$expected" ]; then
    pass "panes_in_tab 5 returns %0 and %1"
else
    fail "panes_in_tab 5 returns %0 and %1" "got '$panes'"
fi

# Test 7: remove_pane %0 then wez_from_tmux %0 fails
remove_pane %0
if wez_from_tmux %0 2>/dev/null; then
    fail "remove_pane %0 then wez_from_tmux %0 fails" "should fail but succeeded"
else
    pass "remove_pane %0 then wez_from_tmux %0 fails"
fi

echo

# ============================================================================
# Group 2: tmux shim tests (mock wezterm context)
# ============================================================================
echo "Group 2: tmux shim tests (mock wezterm context)"
echo "------------------------------------------------"

# Setup mock WezTerm environment
TERM_PROGRAM="WezTerm"; export TERM_PROGRAM
WEZTERM_SHIM_LIB="$SHIM_DIR/lib/pane-map.sh"; export WEZTERM_SHIM_LIB
WEZTERM_SHIM_TAB="5"; export WEZTERM_SHIM_TAB
WEZTERM_SHIM_DIR="$SHIM_DIR"; export WEZTERM_SHIM_DIR
REAL_TMUX=""; export REAL_TMUX
TMUX="/fake/wezcld,0,0"; export TMUX

# Reinitialize for clean state
. "$SHIM_DIR/lib/pane-map.sh"
shim_init
TMUX_PANE=$(alloc_pane_id 100 5); export TMUX_PANE

# Test 1: bin/tmux -V outputs tmux 3.4
version_output=$("$SHIM_DIR/bin/tmux" -V)
if [ "$version_output" = "tmux 3.4" ]; then
    pass "bin/tmux -V outputs tmux 3.4"
else
    fail "bin/tmux -V outputs tmux 3.4" "got '$version_output'"
fi

# Test 2: display-message -p "#{pane_id}" outputs $TMUX_PANE
pane_output=$("$SHIM_DIR/bin/tmux" display-message -p "#{pane_id}")
if [ "$pane_output" = "$TMUX_PANE" ]; then
    pass "display-message -p #{pane_id} outputs \$TMUX_PANE"
else
    fail "display-message -p #{pane_id} outputs \$TMUX_PANE" "got '$pane_output'"
fi

# Test 3: display-message -t target -p "#{pane_id}"
test_pane=$(alloc_pane_id 101 5)
pane_target_output=$("$SHIM_DIR/bin/tmux" display-message -t "$test_pane" -p "#{pane_id}")
if [ "$pane_target_output" = "$test_pane" ]; then
    pass "display-message -t target -p #{pane_id} outputs target"
else
    fail "display-message -t target -p #{pane_id} outputs target" "got '$pane_target_output'"
fi

# Test 4: display-message session_name:window_index
session_output=$("$SHIM_DIR/bin/tmux" display-message -t "$test_pane" -p "#{session_name}:#{window_index}")
if [ "$session_output" = "wezterm:5" ]; then
    pass "display-message session_name:window_index outputs wezterm:5"
else
    fail "display-message session_name:window_index outputs wezterm:5" "got '$session_output'"
fi

# Test 5: No-op commands exit 0
if "$SHIM_DIR/bin/tmux" select-layout even-horizontal 2>/dev/null; then
    pass "select-layout even-horizontal exits 0"
else
    fail "select-layout even-horizontal exits 0" "non-zero exit"
fi

if "$SHIM_DIR/bin/tmux" resize-pane -t "$test_pane" -x 50 2>/dev/null; then
    pass "resize-pane exits 0"
else
    fail "resize-pane exits 0" "non-zero exit"
fi

if "$SHIM_DIR/bin/tmux" set-option -g base-index 1 2>/dev/null; then
    pass "set-option exits 0"
else
    fail "set-option exits 0" "non-zero exit"
fi

echo

# ============================================================================
# Group 3: Passthrough test
# ============================================================================
echo "Group 3: Passthrough test"
echo "-------------------------"

# Create a mock real tmux script
MOCK_TMUX="$(mktemp)"
cat > "$MOCK_TMUX" << 'EOF'
#!/bin/sh
echo "real-tmux-called"
EOF
chmod +x "$MOCK_TMUX"

# Unset shim environment and set REAL_TMUX
unset WEZTERM_SHIM_LIB
REAL_TMUX="$MOCK_TMUX"; export REAL_TMUX

# Test passthrough
passthrough_output=$("$SHIM_DIR/bin/tmux" -V)
if [ "$passthrough_output" = "real-tmux-called" ]; then
    pass "passthrough to real tmux works"
else
    fail "passthrough to real tmux works" "got '$passthrough_output'"
fi

rm -f "$MOCK_TMUX"

echo
echo "Note: split-window, send-keys, and kill-pane require a live WezTerm session."
echo "Run this test inside WezTerm for full coverage."
echo

echo "Results: $PASSED/$TESTS passed"

if [ "$FAILED" -gt 0 ]; then
    exit 1
else
    exit 0
fi
```

**Step 2: Run tests**

Run: `./tests/integration-test.sh`
Expected: All pass

**Step 3: Commit**

```
test: convert integration tests to POSIX sh
```

---

### Task 5: Create `scripts/build-installer.sh`

**Files:**
- Create: `scripts/build-installer.sh`

This script reads source files and generates `install.sh` with embedded heredocs.

**Step 1: Write build script**

```sh
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
```

**Step 2: Run the build script**

Run: `./scripts/build-installer.sh`
Expected: Generates `install.sh` at repo root

**Step 3: Verify generated installer is valid sh**

Run: `sh -n install.sh`
Expected: No syntax errors

**Step 4: Commit**

```
feat(build): add self-extracting installer generator
```

---

### Task 6: Generate and commit `install.sh`

**Files:**
- Modify: `install.sh` (overwritten by build)

**Step 1: Run build script**

Run: `./scripts/build-installer.sh`

**Step 2: Verify syntax**

Run: `sh -n install.sh`

**Step 3: Dry-run test the installer in a temp HOME**

```sh
HOME=$(mktemp -d) sh install.sh
```

Verify:
- `$HOME/.local/share/wezcld/bin/tmux` exists
- `$HOME/.local/share/wezcld/bin/wezcld` exists
- `$HOME/.local/share/wezcld/lib/pane-map.sh` exists
- `$HOME/.local/bin/wezcld` is a wrapper script
- `$HOME/.local/bin/tmux` is a wrapper script

**Step 4: Test uninstall**

```sh
HOME=$(mktemp -d) sh install.sh
HOME=$same_dir sh install.sh --uninstall
```

Verify all files removed.

**Step 5: Commit**

```
chore: generate self-extracting install.sh
```

---

### Task 7: Update `bin/wezcld` for installed context

**Files:**
- Modify: `bin/wezcld`

When running from `~/.local/share/wezcld/bin/wezcld` (installed), the SHIM_DIR resolution already works via the symlink-following loop. But we should also check `$HOME/.local/share/wezcld` as a fallback.

Actually — the current symlink resolution in wezcld already handles this correctly since the wrapper execs the real script, which resolves its own path. No change needed. Skip this task.

---

### Task 8: Final verification

**Step 1: Run all tests**

Run: `./tests/integration-test.sh`
Expected: All pass

**Step 2: Verify all shebangs are #!/bin/sh**

Run: `head -1 bin/wezcld bin/tmux lib/pane-map.sh tests/integration-test.sh`
Expected: All `#!/bin/sh`

**Step 3: Verify no bash-isms remain**

Run: `grep -rn '\[\[' bin/ lib/` — should return nothing
Run: `grep -rn 'local ' bin/ lib/` — should return nothing (we dropped `local`)

**Step 4: Verify install.sh is self-contained**

Run: `grep -c 'PANE_MAP_EOF\|TMUX_SHIM_EOF\|WEZCLD_EOF' install.sh`
Expected: 6 (open + close for each)
