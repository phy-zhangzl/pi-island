# Pi Island

A macOS Dynamic Island–style overlay for [pi](https://github.com/mariozechner/pi-coding-agent) coding sessions in iTerm2.

Pi Island sits above the notch and shows real-time status of your pi agent sessions — thinking, reading, running, editing — with a pixel-art cat companion.

## Features

- **Three states**: static pill → expanded live activity → full session panel
- **Real-time events** via local TCP server (port 47831)
- **Session discovery** from `~/.pi/agent/sessions/`
- **Pixel cat pet** that reacts to agent state
- **Context token usage** display

## Requirements

- macOS 13+
- Swift 5.9+
- MacBook with notch (built-in display)
- [pi](https://github.com/mariozechner/pi-coding-agent) coding agent

## Setup

### 1. Build & Run the overlay

```bash
swift build
.build/debug/PiIsland
```

### 2. Install the pi extension

Copy the extension to your project's pi extensions directory:

```bash
# Per-project (recommended)
mkdir -p .pi/extensions
cp extension/pi-island.ts .pi/extensions/

# Or global
mkdir -p ~/.pi/extensions
cp extension/pi-island.ts ~/.pi/extensions/
```

The extension hooks into pi's lifecycle events and sends state updates to the overlay via `http://127.0.0.1:47831/event`.

## Architecture

```
┌─────────────────────┐     HTTP POST /event     ┌──────────────────┐
│   pi coding agent   │ ───────────────────────▶  │    Pi Island     │
│                     │    (port 47831)           │    (overlay)     │
│  extension/         │                           │                  │
│   pi-island.ts      │                           │  Sources/*.swift │
└─────────────────────┘                           └──────────────────┘
```

### Overlay (Swift)

| File | Purpose |
|------|---------|
| `PiIslandApp.swift` | App entry point, event server init |
| `ContentView.swift` | Root view, AppModel (state management) |
| `IslandView.swift` | Island UI, animations, pixel art components |
| `EventServer.swift` | TCP server for pi events |
| `SessionDiscovery.swift` | Scan `~/.pi/agent/sessions/` |
| `OverlayPlacement.swift` | Notch geometry & window positioning |
| `WindowAccessor.swift` | NSWindow configuration (borderless, statusBar level) |
| `TerminalNavigator.swift` | Terminal focus (placeholder) |

### Extension (TypeScript)

| File | Purpose |
|------|---------|
| `extension/pi-island.ts` | Pi extension that sends lifecycle events to the overlay |

#### Events sent by the extension

| pi event | → Island state | Detail |
|----------|---------------|--------|
| `session_start` | `idle` | Ready |
| `agent_start` | `thinking` | Processing request |
| `tool: read` | `reading` | file path |
| `tool: bash` | `running` | command |
| `tool: edit/write` | `patching` | file path |
| `tool_result (error)` | `error` | Something went wrong |
| `agent_end` | `done` | Task completed |

## Event API

Send events to `POST http://127.0.0.1:47831/event`:

```json
{
  "source": "pi",
  "sessionId": "uuid",
  "projectName": "my-project",
  "sessionName": "my session",
  "cwd": "/path/to/project",
  "state": "thinking",
  "detail": "Processing request",
  "contextTokens": 12000,
  "contextWindow": 200000,
  "timestamp": 1700000000
}
```

States: `idle`, `thinking`, `reading`, `running`, `patching`, `done`, `error`

## License

MIT
