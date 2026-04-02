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

## Build & Run

```bash
swift build
.build/debug/PiIsland
```

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

## Architecture

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

## License

MIT
