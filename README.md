```
 ██╗    ██╗ ███████╗ ███████╗  ██████╗ ██╗     ██████╗
 ██║    ██║ ██╔════╝ ╚══███╔╝ ██╔════╝ ██║     ██╔══██╗
 ██║ █╗ ██║ █████╗     ███╔╝  ██║      ██║     ██║  ██║
 ██║███╗██║ ██╔══╝    ███╔╝   ██║      ██║     ██║  ██║
 ╚███╔███╔╝ ███████╗ ███████╗ ╚██████╗ ███████╗██████╔╝
  ╚══╝╚══╝ ╚══════╝ ╚══════╝  ╚═════╝ ╚══════╝╚═════╝
```

**WezTerm tmux shim for Claude Code agent teams**

## Why

Claude Code uses tmux to manage agent teams, spawning each agent in a separate pane. wezcld intercepts tmux commands and translates them to WezTerm CLI calls, letting you use native WezTerm splits instead of tmux.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/afewyards/wezcld/main/install.sh | sh
```

## Usage

Launch Claude Code with WezTerm integration:

```sh
wezcld
```

When running outside WezTerm, `wezcld` automatically falls back to plain `claude`.

## How it works

**Architecture:**

- **`wezcld` launcher**: Sets fake `TMUX` environment variables and prepends the shim's `bin/` directory to `PATH`
- **`bin/tmux` shim**: Intercepts tmux commands and translates them to `wezterm cli` calls (split-pane, send-text, activate-pane, kill-pane, etc.)
- **Pane ID mapping**: Maintains bidirectional mapping between tmux-style pane IDs (`%0`, `%1`, `%2`, ...) and WezTerm integer pane IDs
- **State persistence**: Stores pane mappings in `~/.local/state/wezcld/pane-map` with atomic counter for ID allocation
- **Passthrough mode**: When not running in WezTerm or without shim environment, passes through to real system tmux

## Supported commands

| Command | Behavior |
|---------|----------|
| `split-window` | Creates WezTerm split via `wezterm cli split-pane` |
| `send-keys` | Sends text to pane via `wezterm cli send-text` |
| `display-message` | Returns mapped pane/session info for Claude |
| `list-panes` | Queries pane map and returns tmux-style pane list |
| `select-pane` | Activates pane via `wezterm cli activate-pane` |
| `kill-pane` | Kills pane via `wezterm cli kill-pane` and cleans up mapping |
| `-V` | Returns `"tmux 3.4"` for version checks |
| `select-layout` | No-op (WezTerm manages layout) |
| `resize-pane` | No-op (WezTerm manages sizing) |
| `set-option` | No-op (shim ignores tmux options) |
| `set-window-option` | No-op (shim ignores tmux options) |
| `has-session` | No-op (always succeeds) |
| `new-session` | No-op (WezTerm session already exists) |
| `new-window` | No-op (WezTerm manages windows) |
| `list-sessions` | No-op (single implicit session) |
| `list-windows` | No-op (WezTerm manages windows) |
| `break-pane` | No-op (not applicable to WezTerm) |
| `join-pane` | No-op (not applicable to WezTerm) |
| `move-window` | No-op (not applicable to WezTerm) |
| `swap-pane` | No-op (not applicable to WezTerm) |

## Requirements

- **jq** (JSON parsing)
- **wezterm CLI** (included with WezTerm)
- **POSIX-compatible shell** (bash, zsh, dash, ash)
- **Claude Code** (the CLI tool from Anthropic)

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/afewyards/wezcld/main/install.sh | sh -s -- --uninstall
```

## Development

**Running tests:**

```sh
./tests/integration-test.sh
```

**Rebuilding installer:**

```sh
./scripts/build-installer.sh
```
