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
# Group 1: it2 shim tests
# ============================================================================
echo "Group 1: it2 shim tests"
echo "-----------------------"

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

# Test 3: it2 session split outputs "Created new pane: fake-session-N"
split_output1=$("$SHIM_DIR/bin/it2" session split 2>&1)
if echo "$split_output1" | grep -qE "^Created new pane: fake-session-[0-9]+$"; then
    pass "it2 session split outputs 'Created new pane: fake-session-N'"
else
    fail "it2 session split outputs 'Created new pane: fake-session-N'" "got '$split_output1'"
fi

# Test 4: it2 session split -v outputs different ID than previous
split_output2=$("$SHIM_DIR/bin/it2" session split -v 2>&1)
if [ "$split_output1" != "$split_output2" ] && echo "$split_output2" | grep -qE "^Created new pane: fake-session-[0-9]+$"; then
    pass "it2 session split -v outputs different ID than previous"
else
    fail "it2 session split -v outputs different ID than previous" "got '$split_output2'"
fi

# Test 5: it2 split --vertical (shortcut) outputs "Created new pane: fake-session-N"
split_shortcut=$("$SHIM_DIR/bin/it2" split --vertical 2>&1)
if echo "$split_shortcut" | grep -qE "^Created new pane: fake-session-[0-9]+$"; then
    pass "it2 split --vertical outputs 'Created new pane: fake-session-N'"
else
    fail "it2 split --vertical outputs 'Created new pane: fake-session-N'" "got '$split_shortcut'"
fi

# Test 6: it2 session send exits 0
if "$SHIM_DIR/bin/it2" session send --session fake-session-0 "hello" 2>&1 >/dev/null; then
    pass "it2 session send exits 0"
else
    fail "it2 session send exits 0" "non-zero exit"
fi

# Test 7: it2 session run exits 0
if "$SHIM_DIR/bin/it2" session run --session fake-session-0 "ls" 2>&1 >/dev/null; then
    pass "it2 session run exits 0"
else
    fail "it2 session run exits 0" "non-zero exit"
fi

# Test 8: it2 session close outputs "Session closed"
close_output=$("$SHIM_DIR/bin/it2" session close --session fake-session-0 2>&1)
if [ "$close_output" = "Session closed" ]; then
    pass "it2 session close outputs 'Session closed'"
else
    fail "it2 session close outputs 'Session closed'" "got '$close_output'"
fi

# Test 9: it2 session list exits 0 and outputs table header
list_output=$("$SHIM_DIR/bin/it2" session list 2>&1)
if echo "$list_output" | grep -qE "Session ID"; then
    pass "it2 session list exits 0 and outputs table header"
else
    fail "it2 session list exits 0 and outputs table header" "got '$list_output'"
fi

# Test 10: it2 vsplit shortcut outputs "Created new pane: fake-session-N"
vsplit_output=$("$SHIM_DIR/bin/it2" vsplit 2>&1)
if echo "$vsplit_output" | grep -qE "^Created new pane: fake-session-[0-9]+$"; then
    pass "it2 vsplit outputs 'Created new pane: fake-session-N'"
else
    fail "it2 vsplit outputs 'Created new pane: fake-session-N'" "got '$vsplit_output'"
fi

# Test 11: it2 --help outputs help text
help_output=$("$SHIM_DIR/bin/it2" --help 2>&1)
if echo "$help_output" | grep -qE "it2 - iTerm2 CLI \(wezcld shim\)"; then
    pass "it2 --help outputs help text"
else
    fail "it2 --help outputs help text" "got '$help_output'"
fi

# Test 12: it2 ls alias exits 0 and outputs table header
ls_output=$("$SHIM_DIR/bin/it2" ls 2>&1)
if echo "$ls_output" | grep -qE "Session ID"; then
    pass "it2 ls alias exits 0 and outputs table header"
else
    fail "it2 ls alias exits 0 and outputs table header" "got '$ls_output'"
fi

# Test 13: it2 send shortcut exits 0
if "$SHIM_DIR/bin/it2" send "hello" 2>&1 >/dev/null; then
    pass "it2 send shortcut exits 0"
else
    fail "it2 send shortcut exits 0" "non-zero exit"
fi

# Test 14: it2 run shortcut exits 0
if "$SHIM_DIR/bin/it2" run "ls" 2>&1 >/dev/null; then
    pass "it2 run shortcut exits 0"
else
    fail "it2 run shortcut exits 0" "non-zero exit"
fi

# Test 15: Unknown commands exit 0
if "$SHIM_DIR/bin/it2" unknown-command --some-flag 2>&1 >/dev/null; then
    pass "unknown commands exit 0"
else
    fail "unknown commands exit 0" "non-zero exit"
fi

# Test 16: Log file exists at $WEZCLD_STATE/it2-calls.log
if [ -f "$WEZCLD_STATE/it2-calls.log" ]; then
    pass "log file exists at \$WEZCLD_STATE/it2-calls.log"
else
    fail "log file exists at \$WEZCLD_STATE/it2-calls.log" "file not found"
fi

# Test 17: Log file has entries
log_lines=$(wc -l < "$WEZCLD_STATE/it2-calls.log" 2>/dev/null || echo "0")
if [ "$log_lines" -gt 0 ]; then
    pass "log file has entries"
else
    fail "log file has entries" "file is empty"
fi

# Test 18: Log entries have [timestamp] ARGV: format
if grep -qE '^\[[0-9T:+-Z]+\] ARGV:' "$WEZCLD_STATE/it2-calls.log" 2>/dev/null; then
    pass "log entries have [timestamp] ARGV: format"
else
    fail "log entries have [timestamp] ARGV: format" "format mismatch"
fi

echo
echo "Results: $PASSED/$TESTS passed"

if [ "$FAILED" -gt 0 ]; then
    exit 1
else
    exit 0
fi
