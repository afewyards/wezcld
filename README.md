```
 ██╗    ██╗ ███████╗ ███████╗  ██████╗ ██╗     ██████╗
 ██║    ██║ ██╔════╝ ╚══███╔╝ ██╔════╝ ██║     ██╔══██╗
 ██║ █╗ ██║ █████╗     ███╔╝  ██║      ██║     ██║  ██║
 ██║███╗██║ ██╔══╝    ███╔╝   ██║      ██║     ██║  ██║
 ╚███╔███╔╝ ███████╗ ███████╗ ╚██████╗ ███████╗██████╔╝
  ╚══╝╚══╝ ╚══════╝ ╚══════╝  ╚═════╝ ╚══════╝╚═════╝
```

**WezTerm it2 shim for Claude Code agent teams**

![wezcld demo](docs/demo.gif)

## Why

Claude Code uses iTerm2 split panes to manage agent teams. wezcld intercepts `it2` CLI commands and translates them to WezTerm CLI calls, letting you use native WezTerm splits instead of iTerm2.

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

- **`wezcld` launcher**: Sets `TERM_PROGRAM=iTerm.app` and puts the shim's `bin/` directory first in `PATH`, then launches Claude with `--teammate-mode tmux`
- **`bin/it2` shim**: Intercepts `it2` CLI commands and logs them to `~/.local/state/wezcld/it2-calls.log`, returning plausible fake responses
- **No mapping layer**: Unlike the old tmux polyfill, the it2 approach needs no pane ID mapping

> **Note:** This is Phase 1 (observation mode). The shim logs all commands to determine exactly what Claude Code sends. Phase 2 will translate these to real `wezterm cli` calls.

## Logged commands

| Command | Fake response |
|---------|---------------|
| `--version` / `app version` | `it2 0.2.3` |
| `session split [-v]` | `Created new pane: fake-session-{N}` |
| `session send` | Silent success |
| `session run` | Silent success |
| `session close` | `Session closed` |
| `session list` | Minimal fake session table |
| `split` / `vsplit` | Alias for `session split` |
| All other commands | Silent success (exit 0) |

Logs are written to `~/.local/state/wezcld/it2-calls.log`.

## Requirements

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
