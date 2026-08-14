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

# Pin the grid key so tests know which state file the shim writes
WEZCLD_LEADER_PANE="${WEZTERM_PANE:-0}"
export WEZCLD_LEADER_PANE
GRID_FILE="$WEZCLD_STATE/grid-panes-$WEZCLD_LEADER_PANE"

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

# Test 14: wezcld --version outputs 'wezcld dev'
version_output=$("$SHIM_DIR/bin/wezcld" --version 2>&1)
if [ "$version_output" = "wezcld dev" ]; then
    pass "wezcld --version outputs 'wezcld dev'"
else
    fail "wezcld --version outputs 'wezcld dev'" "got '$version_output'"
fi

# Test 18: wezcld -v outputs 'wezcld dev'
version_output=$("$SHIM_DIR/bin/wezcld" -v 2>&1)
if [ "$version_output" = "wezcld dev" ]; then
    pass "wezcld -v outputs 'wezcld dev'"
else
    fail "wezcld -v outputs 'wezcld dev'" "got '$version_output'"
fi

echo

# ============================================================================
# Group 1b: Command translation against a stubbed `wezterm` (always run)
# ============================================================================
echo "Group 1b: Command translation (stubbed wezterm)"
echo "-----------------------------------------------"

STUB_DIR="$WEZCLD_STATE/stub-bin"
mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/wezterm" << 'STUB'
#!/bin/sh
# Record argv and, for send-text, stdin, so tests can assert on what was sent.
{
    printf 'ARGV:'
    for a in "$@"; do printf ' [%s]' "$a"; done
    printf '\n'
    if [ "${2:-}" = "send-text" ]; then
        printf 'STDIN:'
        cat
    fi
} >> "$WEZTERM_STUB_LOG"
exit 0
STUB
chmod +x "$STUB_DIR/wezterm"

WEZTERM_STUB_LOG="$WEZCLD_STATE/wezterm-stub.log"
export WEZTERM_STUB_LOG

run_with_stub() {
    : > "$WEZTERM_STUB_LOG"
    PATH="$STUB_DIR:$PATH" "$SHIM_DIR/bin/it2" "$@" >/dev/null 2>&1
}

sent_text() {
    sed -n 's/^STDIN://p' "$WEZTERM_STUB_LOG"
}

# Test 30: a single command argument is forwarded verbatim
run_with_stub session run -s 7 "echo hi"
if [ "$(sent_text)" = "echo hi" ]; then
    pass "session run forwards a single command argument verbatim"
else
    fail "session run forwards a single command argument verbatim" "got '$(sent_text)'"
fi

# Test 31: multi-word arguments keep their boundaries instead of being flattened
run_with_stub session run -s 7 claude -p "do a thing"
if [ "$(sent_text)" = "claude -p 'do a thing'" ]; then
    pass "session run quotes multi-word arguments"
else
    fail "session run quotes multi-word arguments" "got '$(sent_text)'"
fi

# Test 32: shell metacharacters in an argument cannot reach the target shell
run_with_stub session run -s 7 echo 'a; rm -rf /tmp/nope'
if [ "$(sent_text)" = "echo 'a; rm -rf /tmp/nope'" ]; then
    pass "session run neutralises shell metacharacters"
else
    fail "session run neutralises shell metacharacters" "got '$(sent_text)'"
fi

# Test 33: embedded single quotes survive the round trip
run_with_stub session run -s 7 echo "it's"
if [ "$(sent_text)" = "echo 'it'\\''s'" ]; then
    pass "session run escapes embedded single quotes"
else
    fail "session run escapes embedded single quotes" "got '$(sent_text)'"
fi

# Test 34: session run without a target sends nothing
run_with_stub session run "echo hi"
if [ ! -s "$WEZTERM_STUB_LOG" ]; then
    pass "session run without -s sends nothing"
else
    fail "session run without -s sends nothing" "stub was invoked"
fi

# Test 35: session close kills the requested pane
run_with_stub session close -s 42
if grep -q 'ARGV: \[cli\] \[kill-pane\] \[--pane-id\] \[42\]' "$WEZTERM_STUB_LOG"; then
    pass "session close kills the requested pane"
else
    fail "session close kills the requested pane" "got '$(cat "$WEZTERM_STUB_LOG")'"
fi

echo

# ============================================================================
# Group 1c: Uninstall safety (always run, sandboxed HOME)
# ============================================================================
echo "Group 1c: Uninstall safety"
echo "--------------------------"

FAKE_HOME="$WEZCLD_STATE/fake-home"
mkdir -p "$FAKE_HOME/dotfiles" "$FAKE_HOME/.local/bin"

# An rc file symlinked into a dotfiles repo, as stow/chezmoi users have
printf 'export FOO=1\nexport PATH="$HOME/.local/bin:$PATH" # wezcld\n' > "$FAKE_HOME/dotfiles/zshrc"
ln -s "$FAKE_HOME/dotfiles/zshrc" "$FAKE_HOME/.zshrc"

# A real `tmux` and a real `it2` that wezcld must not touch
printf '#!/bin/sh\necho real tmux\n' > "$FAKE_HOME/.local/bin/tmux"
printf '#!/bin/sh\necho real it2\n' > "$FAKE_HOME/.local/bin/it2"
chmod +x "$FAKE_HOME/.local/bin/tmux" "$FAKE_HOME/.local/bin/it2"

HOME="$FAKE_HOME" "$SHIM_DIR/bin/wezcld" --uninstall >/dev/null 2>&1 || true

# Test 36: the rc file is still a symlink into the dotfiles repo
if [ -L "$FAKE_HOME/.zshrc" ]; then
    pass "uninstall keeps a symlinked rc file a symlink"
else
    fail "uninstall keeps a symlinked rc file a symlink" "symlink was replaced"
fi

# Test 37: only the wezcld line was removed
if [ "$(cat "$FAKE_HOME/dotfiles/zshrc")" = "export FOO=1" ]; then
    pass "uninstall removes only the wezcld PATH line"
else
    fail "uninstall removes only the wezcld PATH line" "got '$(cat "$FAKE_HOME/dotfiles/zshrc")'"
fi

# Test 38: a foreign tmux on PATH is left alone
if [ -f "$FAKE_HOME/.local/bin/tmux" ]; then
    pass "uninstall leaves a foreign tmux alone"
else
    fail "uninstall leaves a foreign tmux alone" "tmux was deleted"
fi

# Test 39: a real it2 that wezcld did not write is left alone
if [ -f "$FAKE_HOME/.local/bin/it2" ]; then
    pass "uninstall leaves a foreign it2 alone"
else
    fail "uninstall leaves a foreign it2 alone" "it2 was deleted"
fi

echo

# ============================================================================
# Group 2: Live WezTerm grid layout tests (conditional)
# ============================================================================
if [ "${TERM_PROGRAM:-}" = "WezTerm" ]; then
    echo "Group 2: Live WezTerm grid layout tests"
    echo "----------------------------------------"

    # Clean state for tests
    rm -f "$GRID_FILE"

    # Test 20: First split creates pane above (--top)
    split1=$("$SHIM_DIR/bin/it2" session split -v 2>&1)
    pane1=$(echo "$split1" | sed 's/Created new pane: //')
    if echo "$pane1" | grep -qE "^[0-9]+$"; then
        pass "first split returns valid pane ID ($pane1)"
    else
        fail "first split returns valid pane ID" "got '$split1'"
    fi

    # Test 21: Grid-panes file has 1 entry
    grid_count=$(wc -l < "$GRID_FILE" 2>/dev/null || echo "0")
    grid_count=$(echo "$grid_count" | tr -d ' ')
    if [ "$grid_count" -eq 1 ]; then
        pass "grid-panes has 1 entry after first split"
    else
        fail "grid-panes has 1 entry after first split" "got $grid_count"
    fi

    # Test 22: Second split creates pane to the right
    split2=$("$SHIM_DIR/bin/it2" session split -s "$pane1" 2>&1)
    pane2=$(echo "$split2" | sed 's/Created new pane: //')
    if echo "$pane2" | grep -qE "^[0-9]+$"; then
        pass "second split returns valid pane ID ($pane2)"
    else
        fail "second split returns valid pane ID" "got '$split2'"
    fi

    # Test 23: Third split creates pane to the right (fills row 1)
    split3=$("$SHIM_DIR/bin/it2" session split -s "$pane2" 2>&1)
    pane3=$(echo "$split3" | sed 's/Created new pane: //')
    if echo "$pane3" | grep -qE "^[0-9]+$"; then
        pass "third split returns valid pane ID ($pane3)"
    else
        fail "third split returns valid pane ID" "got '$split3'"
    fi

    # Test 24: Fourth split creates new row (--bottom from pane1)
    split4=$("$SHIM_DIR/bin/it2" session split -s "$pane3" 2>&1)
    pane4=$(echo "$split4" | sed 's/Created new pane: //')
    if echo "$pane4" | grep -qE "^[0-9]+$"; then
        pass "fourth split (new row) returns valid pane ID ($pane4)"
    else
        fail "fourth split (new row) returns valid pane ID" "got '$split4'"
    fi

    # Test 25: Grid-panes file has 4 entries
    grid_count=$(wc -l < "$GRID_FILE" 2>/dev/null || echo "0")
    grid_count=$(echo "$grid_count" | tr -d ' ')
    if [ "$grid_count" -eq 4 ]; then
        pass "grid-panes has 4 entries after 4 splits"
    else
        fail "grid-panes has 4 entries after 4 splits" "got $grid_count"
    fi

    # Test 26: Session close kills pane and removes from grid
    "$SHIM_DIR/bin/it2" session close -s "$pane4" >/dev/null 2>&1
    grid_count=$(wc -l < "$GRID_FILE" 2>/dev/null || echo "0")
    grid_count=$(echo "$grid_count" | tr -d ' ')
    if [ "$grid_count" -eq 3 ]; then
        pass "session close removes pane from grid ($grid_count entries)"
    else
        fail "session close removes pane from grid" "got $grid_count entries"
    fi

    # Test 27: Session run sends command to pane
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
