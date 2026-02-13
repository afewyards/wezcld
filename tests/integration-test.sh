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
# Group 2: Live WezTerm split tests (conditional)
# ============================================================================
if [ "${TERM_PROGRAM:-}" = "WezTerm" ]; then
    echo "Group 2: Live WezTerm split tests"
    echo "----------------------------------"

    # Test 14: it2 session split outputs "Created new pane: <integer>"
    split_output1=$("$SHIM_DIR/bin/it2" session split 2>&1)
    pane_id1=$(echo "$split_output1" | sed 's/Created new pane: //')
    if echo "$split_output1" | grep -qE "^Created new pane: [0-9]+$"; then
        pass "it2 session split outputs 'Created new pane: <integer>'"
    else
        fail "it2 session split outputs 'Created new pane: <integer>'" "got '$split_output1'"
    fi

    # Test 15: Pane ID is a valid integer
    if echo "$pane_id1" | grep -qE "^[0-9]+$"; then
        pass "pane ID is a valid integer"
    else
        fail "pane ID is a valid integer" "got '$pane_id1'"
    fi

    # Test 16: it2 session split -v outputs valid pane ID
    split_output2=$("$SHIM_DIR/bin/it2" session split -v 2>&1)
    pane_id2=$(echo "$split_output2" | sed 's/Created new pane: //')
    if echo "$split_output2" | grep -qE "^Created new pane: [0-9]+$"; then
        pass "it2 session split -v outputs valid pane ID"
    else
        fail "it2 session split -v outputs valid pane ID" "got '$split_output2'"
    fi

    # Test 17: it2 session split -s <id> outputs valid pane ID
    split_output3=$("$SHIM_DIR/bin/it2" session split -s "$pane_id1" 2>&1)
    pane_id3=$(echo "$split_output3" | sed 's/Created new pane: //')
    if echo "$split_output3" | grep -qE "^Created new pane: [0-9]+$"; then
        pass "it2 session split -s <id> outputs valid pane ID"
    else
        fail "it2 session split -s <id> outputs valid pane ID" "got '$split_output3'"
    fi

    # Test 18: it2 session run sends command to target pane
    if "$SHIM_DIR/bin/it2" session run -s "$pane_id1" "echo test" 2>&1 >/dev/null; then
        pass "it2 session run sends command to target pane"
    else
        fail "it2 session run sends command to target pane" "non-zero exit"
    fi

    # Clean up created panes
    wezterm cli kill-pane --pane-id "$pane_id1" 2>/dev/null || true
    wezterm cli kill-pane --pane-id "$pane_id2" 2>/dev/null || true
    wezterm cli kill-pane --pane-id "$pane_id3" 2>/dev/null || true

    echo
else
    echo "Group 2: Live WezTerm split tests (SKIPPED - not in WezTerm)"
    echo
fi

echo
echo "Results: $PASSED/$TESTS passed"

if [ "$FAILED" -gt 0 ]; then
    exit 1
else
    exit 0
fi
