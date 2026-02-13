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
WEZCLD_STATE="$(mktemp -d)"
export WEZCLD_STATE
trap 'rm -rf "$WEZCLD_STATE"' EXIT

echo "Testing wezcld - it2 shim"
echo "=========================="
echo

# ============================================================================
# Group 1: Unit tests (always run)
# ============================================================================
echo "Group 1: Unit tests"
echo "-------------------"

# Test 1: it2 --version outputs "it2 0.2.3"
version_output=$("$SHIM_DIR/bin/it2" --version 2>&1)
if [ "$version_output" = "it2 0.2.3" ]; then
    pass "it2 --version outputs 'it2 0.2.3'"
else
    fail "it2 --version outputs 'it2 0.2.3'" "got '$version_output'"
fi

# Test 2: it2 app version outputs "it2 0.2.3"
app_version_output=$("$SHIM_DIR/bin/it2" app version 2>&1)
if [ "$app_version_output" = "it2 0.2.3" ]; then
    pass "it2 app version outputs 'it2 0.2.3'"
else
    fail "it2 app version outputs 'it2 0.2.3'" "got '$app_version_output'"
fi

# Test 3: it2 session send exits 0
if "$SHIM_DIR/bin/it2" session send --session fake-session-0 "hello" 2>&1 >/dev/null; then
    pass "it2 session send exits 0"
else
    fail "it2 session send exits 0" "non-zero exit"
fi

# Test 4: it2 session close outputs "Session closed"
close_output=$("$SHIM_DIR/bin/it2" session close --session fake-session-0 2>&1)
if [ "$close_output" = "Session closed" ]; then
    pass "it2 session close outputs 'Session closed'"
else
    fail "it2 session close outputs 'Session closed'" "got '$close_output'"
fi

# Test 5: it2 session list exits 0 and outputs table header
list_output=$("$SHIM_DIR/bin/it2" session list 2>&1)
if echo "$list_output" | grep -qE "Session ID"; then
    pass "it2 session list exits 0 and outputs table header"
else
    fail "it2 session list exits 0 and outputs table header" "got '$list_output'"
fi

# Test 6: it2 --help outputs help text
help_output=$("$SHIM_DIR/bin/it2" --help 2>&1)
if echo "$help_output" | grep -qE "it2 - iTerm2 CLI \(wezcld shim\)"; then
    pass "it2 --help outputs help text"
else
    fail "it2 --help outputs help text" "got '$help_output'"
fi

# Test 7: it2 ls alias exits 0 and outputs table header
ls_output=$("$SHIM_DIR/bin/it2" ls 2>&1)
if echo "$ls_output" | grep -qE "Session ID"; then
    pass "it2 ls alias exits 0 and outputs table header"
else
    fail "it2 ls alias exits 0 and outputs table header" "got '$ls_output'"
fi

# Test 8: it2 send shortcut exits 0
if "$SHIM_DIR/bin/it2" send "hello" 2>&1 >/dev/null; then
    pass "it2 send shortcut exits 0"
else
    fail "it2 send shortcut exits 0" "non-zero exit"
fi

# Test 9: it2 run shortcut exits 0
if "$SHIM_DIR/bin/it2" run "ls" 2>&1 >/dev/null; then
    pass "it2 run shortcut exits 0"
else
    fail "it2 run shortcut exits 0" "non-zero exit"
fi

# Test 10: Unknown commands exit 0
if "$SHIM_DIR/bin/it2" unknown-command --some-flag 2>&1 >/dev/null; then
    pass "unknown commands exit 0"
else
    fail "unknown commands exit 0" "non-zero exit"
fi

# Test 11: Log file exists at $WEZCLD_STATE/it2-calls.log
if [ -f "$WEZCLD_STATE/it2-calls.log" ]; then
    pass "log file exists at \$WEZCLD_STATE/it2-calls.log"
else
    fail "log file exists at \$WEZCLD_STATE/it2-calls.log" "file not found"
fi

# Test 12: Log file has entries
log_lines=$(wc -l < "$WEZCLD_STATE/it2-calls.log" 2>/dev/null || echo "0")
if [ "$log_lines" -gt 0 ]; then
    pass "log file has entries"
else
    fail "log file has entries" "file is empty"
fi

# Test 13: Log entries have [timestamp] ARGV: format
if grep -qE '^\[[0-9T:+-Z]+\] ARGV:' "$WEZCLD_STATE/it2-calls.log" 2>/dev/null; then
    pass "log entries have [timestamp] ARGV: format"
else
    fail "log entries have [timestamp] ARGV: format" "format mismatch"
fi

echo

# ============================================================================
# Group 2: Live WezTerm grid layout tests (conditional)
# ============================================================================
if [ "${TERM_PROGRAM:-}" = "WezTerm" ]; then
    echo "Group 2: Live WezTerm grid layout tests"
    echo "----------------------------------------"

    # Clean state for tests
    rm -f "$WEZCLD_STATE/grid-panes"

    # Test 14: First split creates pane above (--top)
    split1=$("$SHIM_DIR/bin/it2" session split -v 2>&1)
    pane1=$(echo "$split1" | sed 's/Created new pane: //')
    if echo "$pane1" | grep -qE "^[0-9]+$"; then
        pass "first split returns valid pane ID ($pane1)"
    else
        fail "first split returns valid pane ID" "got '$split1'"
    fi

    # Test 15: Grid-panes file has 1 entry
    grid_count=$(wc -l < "$WEZCLD_STATE/grid-panes" 2>/dev/null || echo "0")
    grid_count=$(echo "$grid_count" | tr -d ' ')
    if [ "$grid_count" -eq 1 ]; then
        pass "grid-panes has 1 entry after first split"
    else
        fail "grid-panes has 1 entry after first split" "got $grid_count"
    fi

    # Test 16: Second split creates pane to the right
    split2=$("$SHIM_DIR/bin/it2" session split -s "$pane1" 2>&1)
    pane2=$(echo "$split2" | sed 's/Created new pane: //')
    if echo "$pane2" | grep -qE "^[0-9]+$"; then
        pass "second split returns valid pane ID ($pane2)"
    else
        fail "second split returns valid pane ID" "got '$split2'"
    fi

    # Test 17: Third split creates pane to the right (fills row 1)
    split3=$("$SHIM_DIR/bin/it2" session split -s "$pane2" 2>&1)
    pane3=$(echo "$split3" | sed 's/Created new pane: //')
    if echo "$pane3" | grep -qE "^[0-9]+$"; then
        pass "third split returns valid pane ID ($pane3)"
    else
        fail "third split returns valid pane ID" "got '$split3'"
    fi

    # Test 18: Fourth split creates new row (--bottom from pane1)
    split4=$("$SHIM_DIR/bin/it2" session split -s "$pane3" 2>&1)
    pane4=$(echo "$split4" | sed 's/Created new pane: //')
    if echo "$pane4" | grep -qE "^[0-9]+$"; then
        pass "fourth split (new row) returns valid pane ID ($pane4)"
    else
        fail "fourth split (new row) returns valid pane ID" "got '$split4'"
    fi

    # Test 19: Grid-panes file has 4 entries
    grid_count=$(wc -l < "$WEZCLD_STATE/grid-panes" 2>/dev/null || echo "0")
    grid_count=$(echo "$grid_count" | tr -d ' ')
    if [ "$grid_count" -eq 4 ]; then
        pass "grid-panes has 4 entries after 4 splits"
    else
        fail "grid-panes has 4 entries after 4 splits" "got $grid_count"
    fi

    # Test 20: Session close kills pane and removes from grid
    "$SHIM_DIR/bin/it2" session close -s "$pane4" >/dev/null 2>&1
    grid_count=$(wc -l < "$WEZCLD_STATE/grid-panes" 2>/dev/null || echo "0")
    grid_count=$(echo "$grid_count" | tr -d ' ')
    if [ "$grid_count" -eq 3 ]; then
        pass "session close removes pane from grid ($grid_count entries)"
    else
        fail "session close removes pane from grid" "got $grid_count entries"
    fi

    # Test 21: Session run sends command to pane
    if "$SHIM_DIR/bin/it2" session run -s "$pane1" "echo test" 2>&1 >/dev/null; then
        pass "session run sends command to target pane"
    else
        fail "session run sends command to target pane" "non-zero exit"
    fi

    # Clean up all created panes
    wezterm cli kill-pane --pane-id "$pane1" 2>/dev/null || true
    wezterm cli kill-pane --pane-id "$pane2" 2>/dev/null || true
    wezterm cli kill-pane --pane-id "$pane3" 2>/dev/null || true

    echo
else
    echo "Group 2: Live WezTerm grid layout tests (SKIPPED - not in WezTerm)"
    echo
fi

echo
echo "Results: $PASSED/$TESTS passed"

if [ "$FAILED" -gt 0 ]; then
    exit 1
else
    exit 0
fi
