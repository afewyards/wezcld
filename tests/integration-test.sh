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
