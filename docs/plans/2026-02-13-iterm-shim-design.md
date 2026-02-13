# Design: Replace tmux polyfill with it2 shim

## Goal

Replace the tmux polyfill (bin/tmux + lib/pane-map.sh) with an it2 CLI shim.
Claude Code has native iTerm2 support via the `it2` CLI — simpler surface area than tmux.

## Motivation

- it2 CLI has ~5 commands vs tmux's ~15 handled subcommands
- Eliminates pane-map bidirectional ID mapping layer
- Smaller, more maintainable codebase

## Approach: Observe-then-build (two phases)

### Phase 1: Logging shim

**bin/it2** — logs every invocation, returns plausible fake output.

Fake responses by subcommand:

| Command | Fake output |
|---------|-------------|
| `--version` / `app version` | `it2 0.2.3` |
| `session split [-v]` / `split [--vertical]` | `Created new pane: fake-session-{counter}` |
| `session send` | silent, exit 0 |
| `session close` | `Session closed`, exit 0 |
| `session list` | minimal fake session table |
| `session run` | silent, exit 0 |
| anything else | exit 0 |

Log format: `[ISO-timestamp] ARGV: ... | EXIT: N | STDOUT: ...`
Log location: `~/.local/state/wezcld/it2-calls.log`

**bin/wezcld** launcher changes:
- Set `TERM_PROGRAM=iTerm.app` (drop `TMUX=/fake/wezcld,0,0`)
- Remove `TMUX_PANE`, `WEZTERM_SHIM_LIB`, `WEZTERM_SHIM_TAB`
- Keep prepending shim dir to PATH
- Pass `--teammate-mode tmux` to claude

**Remove:**
- `bin/tmux`
- `lib/pane-map.sh`

### Phase 2: Real shim (separate session)

After observing logs from Phase 1:
1. Identify exact commands Claude Code sends
2. Map each to `wezterm cli` equivalent
3. Determine if session ID format matters
4. Build real translator

## Open questions (answered by Phase 1 logs)

- Does Claude Code check `ITERM_SESSION_ID` or `LC_TERMINAL` env vars?
- Does it validate session ID format on subsequent calls?
- Does it use shortcuts (`it2 split`) or full paths (`it2 session split`)?
- What happens when it sends text to a fake session?
- Does it call `it2 session list` for discovery?
