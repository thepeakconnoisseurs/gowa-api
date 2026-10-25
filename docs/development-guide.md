# Development Guide — GoWA (Go WhatsApp Web Multi-Device)

> Generated: 2026-06-17 · Scan: exhaustive

## Prerequisites

| Requirement | Version / Detail |
|---|---|
| **Go** | 1.25.5+ (the module declares `go 1.25.5`; README notes 1.24+ works for building) |
| **FFmpeg** | Required — video thumbnails/compression, audio duration/waveform, PTT Opus transcode, sticker WebP. (`ffmpeg` + `ffprobe`) |
| **libwebp** | Required for stickers — `cwebp` (encode), `webpmux` (frame extract), `dwebp` (decode) |
| **poppler-utils** (optional) | `pdftoppm` for PDF document thumbnails (ImageMagick `convert` is the fallback) |
| **CGO toolchain** | Default build uses CGO (`go-sqlite3`); needs `gcc`/`musl-dev`. Use `-tags purego` for CGO-free builds. |

### OS-specific install

- **Linux (Debian/Ubuntu):** `sudo apt update && sudo apt install ffmpeg webp` (+ `poppler-utils` for PDFs, `imagemagick` as PDF fallback).
- **macOS:** `brew install ffmpeg webp` then `export CGO_CFLAGS_ALLOW="-Xpreprocessor"` (fixes the macOS `pkg-config` flag error).
- **Windows:** WSL strongly recommended. Install `ffmpeg` and `libwebp`, add their `bin` to PATH.

> Local runtime paths are relative to the process **cwd**, so **always run from `src/`** (so `storages/` and
> `statics/` resolve correctly). Docker runs use root-level `./storages` + `./statics` instead.

## Getting started (local)

```bash
# 1. Clone
git clone https://github.com/aldinokemal/go-whatsapp-web-multidevice
cd go-whatsapp-web-multidevice/src      # ◀ Go module root

# 2. Configure (optional — defaults work for dev)
cp .env.example .env
#   edit .env: set WHATSAPP_WEBHOOK if needed, APP_BASIC_AUTH for auth, etc.

# 3. Run REST mode (API + UI)
go run . rest                            # → http://localhost:3000

#   — or MCP mode (SSE server) —
go run . mcp                             # → http://localhost:8080/sse
```

Open `http://localhost:3000`, scan the QR with your phone (WhatsApp → Linked Devices → Link a Device), and the
account becomes a "device" you can target via the API.

> ⚠️ **Run only ONE mode per process.** whatsmeow cannot safely share session state between REST and MCP in the
> same process. Run separate processes/containers per mode.

## Common commands

All run from `src/`:

| Task | Command |
|---|---|
| Run REST (dev) | `go run . rest` |
| Run MCP (dev) | `go run . mcp` |
| Build binary | `go build -o whatsapp` (Linux/macOS) · `go build -o whatsapp.exe` (Windows) |
| Run the binary | `./whatsapp rest` · `./whatsapp mcp` |
| See all flags | `./whatsapp --help` |
| Tidy modules | `go mod tidy` |
| Vet | `go vet ./...` |
| Run all tests | `go test ./...` |
| Run one package's tests | `go test ./usecase/...` |
| Verbose tests | `go test -v ./infrastructure/chatstorage/...` |
| Hot reload (dev) | `air` (uses `.air.toml`; excludes `statics`/`storages`) |
| purego (CGO-free) build | `CGO_ENABLED=0 go build -tags purego -o whatsapp` |
| Cross-compile ARMv6 | `CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=6 go build -tags purego -o whatsapp-armv6` |
| Cross-compile ARMv7 | `CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7 go build -tags purego -o whatsapp-armv7` |

## Configuration

Config priority (highest → lowest): **CLI flags > environment variables (Viper) > `.env` file > compiled defaults**
(in `config/settings.go`). Bindings are package globals; Cobra binds flags directly to `config.*`, and `initEnvConfig`
overlays Viper values where set. See [architecture.md](./architecture.md) and the full flag table in
[deployment-guide.md](./deployment-guide.md).

Key dev-time defaults:

| Setting | Default | Env var |
|---|---|---|
| App port / host | `3000` / `0.0.0.0` | `APP_PORT` / `APP_HOST` |
| App OS name (WhatsApp device label) | `GOWA` | `APP_OS` |
| Debug logging | `false` | `APP_DEBUG` |
| Chat DB | `file:storages/whatsapp.db` | `DB_URI` |
| App version | `v8.8.0` | — (hard-coded in `config/settings.go`) |

## Project conventions for contributors

- **Go module root is `src/`.** Repo root is not. Run all Go commands from `src/`.
- **Mutable package globals** for config/clients/repos/usecases — match this pattern; do not introduce a DI container piecemeal.
- **Clean-architecture dependency direction:** `ui → usecase → domains`; `infrastructure → domains`. Nobody imports `ui`/`cmd`.
- **Usecase flow:** validate first (`validations.Validate*`), then resolve device/client from context, then execute, then shape a typed response.
- **Device scoping:** device-scoped REST routes must pass `whatsapp.ContextWithDevice(c.UserContext(), getDeviceFromCtx(c))`. MCP resolves the default device via `helpers.ContextWithDefaultDevice`.
- **Optional boolean filters** use `*bool` so `nil` = "not provided".
- **`domains/` holds DTOs + interfaces only** — no executable business logic there.
- **Chat-storage migrations** are Go string literals in `sqlite_repository.go::getMigrations()`, **append-only**.
- **`pkg/error`** package name is literally `error`; import with an alias like `pkgError`.

## Testing approach

- **Colocated `*_test.go`** next to source (47 test files).
- **Table-driven** with `testify/assert` (+ occasional `testify/suite`).
- **SQL mocking** via `DATA-DOG/go-sqlmock` for repository tests.
- **Deterministic concurrency:** background workers expose injectable seams — interfaces (e.g. `presencePulseClient`,
  `presencePulseDeviceSource`, `sendMessageFn`, `submitWebhookFn`, `getChatwootClientFn`) and injectable
  `now()`/`sleep()` — so tests avoid real timers/network.
- **Serial for globals:** tests that mutate config / package globals / background-worker state run **serial** and
  restore prior state with `defer`. Do not parallelize these.

> **No CI test/lint workflow exists** (`.github/workflows/` only builds images/releases). Run `go test ./...` and
> `go vet ./...` locally before pushing.

## Debugging tips

- Set `APP_DEBUG=true` (`-d`) to raise `WhatsappLogLevel` to `DEBUG` and enable Fiber request logging.
- The `filteredLogger` (`infrastructure/whatsapp/logger.go`) downgrades the noisy websocket-EOF error to Debug
  (auto-reconnect fires within ~1s) — it's expected, not a bug.
- QR login PNGs are written to `statics/qrcode/` and auto-deleted after the code duration.
- `/health` (root, ignores base path) returns 200 only if `DeviceManager.IsHealthy()`.
- whatsmeow's own session DB is `storages/whatsapp.db` — deleting it forces a fresh QR login (loses session).
