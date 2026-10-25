# Architecture — GoWA (Go WhatsApp Web Multi-Device)

> Generated: 2026-06-17 · Scan: exhaustive · This document is the authoritative architectural reference for AI-assisted work.

## Executive summary

GoWA is a **clean-architecture (hexagonal) Go backend** that turns the `whatsmeow` WhatsApp multi-device client
into three programmable surfaces — a Fiber **REST API**, an **MCP SSE server**, and an embedded **Vue UI + WebSocket**
stream — plus a deep **Chatwoot** integration. Dependency direction is strictly inward:
**adapters (`ui/`) → use cases (`usecase/`) → domain contracts (`domains/`)**, with `infrastructure/` providing
the concrete whatsmeow, SQLite, and Chatwoot implementations of those contracts.

A defining trait: the **entire object graph is mutable package globals** wired once in `cmd.initApp()`. There is no
DI container and `main()` does not inject dependencies — Cobra's `OnInitialize` callbacks build everything. Device
identity (which WhatsApp account a request targets) travels through `context.Context`, not arguments, which is what
lets the same use cases serve both REST (multi-device) and MCP (default-device).

```
                ┌─────────────────── ADAPTERS (ui/) ───────────────────┐
   HTTP client → │ rest/ (Fiber)   mcp/ (mcp-go SSE)   websocket/ (/ws) │
                └──────────────────────────┬───────────────────────────┘
                                           │  context.Context{device}
                ┌──────────────────────────▼───────────────────────────┐
   request  →   │              usecase/  (business orchestration)        │  → validates → resolves
                │              validations/ (ozzo rules)                 │    device/client →
                └──────────────────────────┬───────────────────────────┘    executes → shapes DTO
                                           │  domain interfaces
                ┌──────────────────────────▼───────────────────────────┐
   contracts    │              domains/  (DTOs + interfaces, no logic)   │  ◄── the hexagon core
                └──────────────────────────┬───────────────────────────┘
                                           │  implemented by
                ┌──────────────────────────▼───────────────────────────┐
   side-effects │  infrastructure/whatsapp   infrastructure/chatstorage   │
                │  (whatsmeow: device mgr,   (SQLite repo: chats, msgs,   │
                │   events, webhooks)         devices, chatwoot links)    │
                │  infrastructure/chatwoot (+pgimport)                     │
                └────────────────────────────────────────────────────────┘
                                           │
                          pkg/  (error, sqlite driver select, utils)  — cross-cutting
```

## Technology stack

See [project-overview.md](./project-overview.md#technology-stack) for the full dependency table. Key architectural
choices:

- **Fiber v2** for HTTP — fast, middleware pipeline (recovery, timeout, basic-auth, device resolution, CORS).
- **`whatsmeow`** as the WhatsApp engine — one `*whatsmeow.Client` per linked account, wrapped in a `DeviceInstance`
  and held in a `DeviceManager` registry.
- **SQLite** as the default chat/session store (CGO `go-sqlite3`, swappable to pure-Go `modernc.org/sqlite` via
  `-tags purego`). Optional **separate keys DB** (`DB_KEYS_URI`) for session-key acceleration; optional **Postgres**
  (`CHATWOOT_IMPORT_DB_URI`) for direct Chatwoot history import.
- **Cobra + Viper** — `rest` and `mcp` subcommands self-register via `init()` side effects; config priority is
  **flags > env > `.env` > compiled defaults**.

## Architecture pattern: layered clean architecture

### Layers and their contracts

| Layer | Package(s) | Owns | Must NOT |
|---|---|---|---|
| **Entry** | `main.go`, `cmd/` | `//go:embed` views, Cobra root/subcommands, global wiring (`initApp`), lifecycle (reconnect, presence pulse) | hold business rules |
| **Adapters** | `ui/rest`, `ui/mcp`, `ui/websocket` | request parsing/binding, transport-specific concerns, calling use cases, shaping responses | contain business logic |
| **Validation** | `validations/` | ozzo-validation rules per request type | call whatsmeow or storage |
| **Use cases** | `usecase/` | business orchestration: validate → resolve device/client → execute → shape response | import Fiber / mcp-go / transport types |
| **Domain** | `domains/` | DTOs (request/response entities) and interfaces — the abstract contracts | contain executable business logic (some whatsmeow types leak into contracts; follow existing patterns) |
| **Infrastructure** | `infrastructure/whatsapp`, `infrastructure/chatstorage`, `infrastructure/chatwoot` | concrete implementations: whatsmeow wrapper, SQLite repository, Chatwoot REST client + pgimport | define business policy (only mechanics) |
| **Shared** | `pkg/error`, `pkg/sqlite`, `pkg/utils` | cross-cutting helpers, typed errors, SQLite driver selection | depend upward |

### The dependency rule

Imports point **inward and downward only**: `ui → usecase → domains`; `infrastructure → domains`; nobody imports
`ui` or `cmd`. The use case layer is the single business boundary and is **transport-agnostic** — that is why REST
and MCP share the exact same `serviceX` implementations.

### Mutable package globals (intentional, not accidental)

`cmd` holds the object graph as module-level `var`s populated by `initApp()`:
`whatsappCli`, `chatStorageDB`, `chatStorageRepo`, and eight use cases
(`appUsecase`, `chatUsecase`, `sendUsecase`, `userUsecase`, `messageUsecase`, `groupUsecase`,
`newsletterUsecase`, `deviceUsecase`). Likewise `config/settings.go` is entirely package globals. This is a
deliberate trade-off: simple wiring, no DI ceremony, at the cost of implicit coupling. **Do not introduce a DI
container piecemeal** — match the existing pattern.

### `initApp()` wiring sequence

1. If `AppDebug`: set `WhatsappLogLevel="DEBUG"` + `logrus.SetLevel(Debug)`.
2. `utils.CreateFolder(PathQrCode, PathSendItems, PathStorages, PathMedia)` — ensure runtime dirs.
3. `initChatStorage()` — open chat-storage SQLite (single conn: `MaxOpenConns(1)`, `MaxIdleConns(1)`), ping, `Fatalf` on failure.
4. `chatstorage.NewStorageRepository(db)` + `InitializeSchema()` — run pending migrations.
5. `whatsapp.InitWaDB(ctx, DBURI)` — primary whatsmeow `sqlstore.Container`; separate keys container if `DBKeysURI != ""`.
6. `whatsapp.InitWaCLI(...)` — build the primary `*whatsmeow.Client` (auto-reconnect, auto-trust).
7. `whatsapp.GetDeviceManager()` + `dm.LoadExistingDevices(ctx)` — restore multi-device registry from persisted `DeviceRecord`s.
8. Construct all eight use cases with their repository/manager dependencies.

`initEnvConfig()` runs **before** `initApp` in the `OnInitialize` chain, overlaying Viper env values onto the
config globals. `time.Local = time.UTC` is forced process-wide.

## Data architecture

Full schema in [data-models-gowa.md](./data-models-gowa.md). Summary:

- **Two SQLite databases** by default:
  - **`whatsapp.db`** (`DB_URI`) — owned by whatsmeow: device sessions, identity keys, messages state. Managed by whatsmeow's `sqlstore`.
  - **`chatstorage.db`** (`ChatStorageURI`, compile-time default) — GoWA's own read-model: `chats`, `messages`,
    `message_reactions`, `message_edits`, `devices`, `chatwoot_message_links`, `chatwoot_forward_queue`. Schema
    evolved via **29 inline Go-string migrations** in `sqlite_repository.go::getMigrations()` (append-only — never
    insert mid-list).
- **Optional keys DB** (`DB_KEYS_URI`) — separate whatsmeow container for session/identity/pre-key acceleration,
  so privacy tokens survive restarts across long-lived sessions.
- **All application tables are device-scoped** — `(device_id, ...)` composite primary keys. The whatsmeow identity
  stored is `client.Store.ID.ToNonAD().String()` (post-login), **not** `instance.ID()` (the internal UUID alias).
- **WAL + foreign keys** are enabled at the connection-URI level by `pkg/sqlite.FormatChatStorageURI`
  (CGO: `_journal_mode=WAL&_busy_timeout=5000&_foreign_keys=on`; purego: equivalent `_pragma=...` forms).
- **`message_edits`** declares a composite FK → `messages` `ON DELETE CASCADE`; chat deletion transactionally
  cascades through reactions/edits/links/messages.

### JID identity: `@s.whatsapp.net` vs `@lid` (critical)

Modern WhatsApp uses privacy-preserving **LID JIDs** (`<opaque>@lid`) alongside classic **phone JIDs**
(`<phone>@s.whatsapp.net`). `whatsapp.NormalizeJIDFromLID(ctx, jid, client)` is the single normalization seam:
it resolves `@lid` → phone JID via `client.Store.LIDs.GetPNForLID` whenever possible, and is called pervasively
in event handlers, storage, and webhook builders. **Anti-pattern:** never use raw `@lid` JIDs for DB lookups —
normalize first. When LID cannot be resolved (e.g. Chatwoot identity), the full `@lid` string is preserved so the
downstream client takes its LID branch rather than misclassifying it as a phone number.

## API design

Full surface in [api-contracts-gowa.md](./api-contracts-gowa.md). Architecturally:

- **REST** is the primary, widest surface. ~77 routes grouped by resource (App/Login, User, Send, Message, Group,
  Newsletter, Chat, Device, Chatwoot) under an optional `APP_BASE_PATH`.
- **Device scoping** is the multi-tenant axis. `middleware.DeviceMiddleware` resolves the target account from
  `X-Device-Id` header → `?device_id=` query → default/only device, then injects it into context via
  `whatsapp.ContextWithDevice`. All device-scoped routes ride on this. **MCP has no device header** — every tool
  resolves the default/only device via `mcpHelpers.ContextWithDefaultDevice`, so MCP is effectively single-device.
- **Standard JSON envelope** (`utils.ResponseData`): `{ code, message, results }` with HTTP status driven by a
  `json:"-"` `Status` field. Error codes are stable strings (e.g. `DEVICE_NOT_FOUND`, `VALIDATION_ERROR`,
  `WA_REACHOUT_TIMELOCK`).
- **Validation first:** every use case method calls `validations.Validate*` before any side-effect.
- **Media** flows through multipart forms (image/file/video/sticker/audio) **or** remote URLs; heavy processing
  (compress, thumbnail, sticker→WebP, audio→Opus, PDF thumb) happens in `usecase/send` via external binaries.

### Send pipeline (the hottest path)

```
REST/MCP request → validations.Validate*  → usecase.Send*
  → resolve device/client from context
  → mentions/ghost-mentions/@everyone resolution (device-scoped)
  → media processing (ffmpeg/cwebp/pdftoppm)
  → whatsapp.SendMessageWithReachoutRetry   (single retry on WA error 463 after SubscribePresence pre-warm)
  → normalize errors → pkgError.ErrWaReachoutTimelock
  → async store sent message (2s-timeout detached context, device-scoped)  [fire-and-forget]
  → return GenericResponse{ message_id, status }
```

## Event / async architecture

Incoming WhatsApp events flow through a single dispatch function `handler(ctx, instance, rawEvt)` registered per
client, which type-switches to per-event handlers in `infrastructure/whatsapp/event_*.go`. Each forwarding path
launches a goroutine with a 30s detached context. Three async subsystems run alongside:

| Subsystem | Starter | Purpose |
|---|---|---|
| **Webhook fan-out** | per-event goroutine | `forwardPayloadToConfiguredWebhooks` → HMAC-signed POST to each `WHATSAPP_WEBHOOK` URL (5 retries, exp backoff), gated by `WHATSAPP_WEBHOOK_EVENTS` whitelist |
| **Chatwoot forward-retry worker** | `StartChatwootForwardRetryWorker(repo)` | ticks every 30s, replays durable `chatwoot_forward_queue` rows that failed transiently (exp backoff, capped 1h); queue is persisted in SQLite, survives restarts |
| **Presence pulse scheduler** | `StartPresencePulseScheduler` (config-gated, `sync.Once`) | cycles each connected device `available` → `unavailable` on `WHATSAPP_PRESENCE_PULSE_INTERVAL` (default 24h) for `…_DURATION` (default 5m), keeping accounts "warm" for typing/peer-presence |
| **Auto-reconnect** | whatsmeow `EnableAutoReconnect` + `helpers.SetAutoConnectAfterBooting` | reconnects dropped sessions; noisy websocket-EOF errors are downgraded to Debug by `filteredLogger` |

`process time.Local = time.UTC` everywhere; durations parsed as `time.Duration`.

## Chatwoot integration architecture

Two backends, selected by `CHATWOOT_IMPORT_DB_URI`:

- **REST path** (`infrastructure/chatwoot/client.go`, `sync.go`) — replays messages through Chatwoot's public API.
  Used for **live forwarding** (always) and **history sync** when `CHATWOOT_IMPORT_DB_URI` is blank.
- **Direct-Postgres path** (`infrastructure/chatwoot/pgimport/`) — INSERTs directly into Chatwoot's Rails schema to
  preserve original timestamps/senders/group subjects. Used **only for history backfill** when the DB URI is set.
  Never used for live forwarding.

Both paths agree on identity via the `gowa_whatsapp_jid` custom attribute and the `WAID:<id>` `source_id` convention,
so the `chatwoot_message_links` table (the integration backbone) maps WhatsApp↔Chatwoot rows regardless of which
path created them. Echo-loop prevention uses a process-global `sentMessageIDs` `sync.Map` with a 5-min TTL.

## Component overview

See [component-inventory.md](./component-inventory.md) for the full module map. Headline components:

- `whatsapp.DeviceManager` — registry of active `*DeviceInstance`s; persist/load/create/purge; `ResolveDevice`.
- `whatsapp.DeviceInstance` — per-account client + state + scoped `deviceChatStorage` repo.
- `chatstorage.SQLiteRepository` — implements `IChatStorageRepository`; chats/messages/reactions/edits/devices/links/queue + 29 inline migrations.
- `whatsapp.handler` — the single event dispatcher.
- `whatsapp.StartChatwootForwardRetryWorker` / `StartPresencePulseScheduler` — background workers.
- `chatwoot.SyncService` / `pgimport.Importer` — the two history-sync backends.
- `middleware.DeviceMiddleware` — the multi-device scoping layer.

## Development workflow

Commands run from `src/` (the Go module root):

```bash
cd src
go run . rest                       # REST API mode (dev)
go run . mcp                        # MCP SSE mode (dev)
go build -o whatsapp                # build binary
go test ./...                       # all tests
go vet ./...                        # vet
go mod tidy                         # tidy deps
```

Tests are colocated `*_test.go`, mostly table-driven with `testify/assert` (+ occasional `testify/suite`); tests
that mutate config/globals/worker state stay **serial** and restore via `defer`. See
[development-guide.md](./development-guide.md).

## Deployment architecture

- **Docker** — two-stage Alpine build (`docker/golang.Dockerfile`): builder `golang:1.25-alpine3.23` + CGO musl
  toolchain; runtime `alpine:3.23` + `ffmpeg libwebp-tools poppler-utils tzdata su-exec`, non-root `gowauser`
  (uid 20001 / gid 20000). `entrypoint.sh` fixes volume ownership then drops privileges via `su-exec`.
- **docker-compose** — builds `gowa-api:latest`, exposes `127.0.0.1:3500:3000`, mounts `./storages` + `./statics`,
  loads `src/.env`, networks `n8n-tpc` (external) + `gowa-api` (bridge).
- **CI/CD** — three tag/manual workflows: `build-docker-image.yaml` (multi-arch amd/arm/armv7 + manifest merge),
  `release.yml` (GoReleaser, tag-guarded, configs generated into `/tmp`), `set-latest-tag.yaml` (manual `:latest`
  promotion). **There is no PR workflow running `go test`/`go vet`/lint** — quality gating is manual.

See [deployment-guide.md](./deployment-guide.md).

## Testing strategy

- **Unit/table-driven** — `*_test.go` next to source; `testify/assert` + `testify/suite`.
- **SQL mocking** — `DATA-DOG/go-sqlmock` for repository tests.
- **Seams for concurrency** — background workers expose injectable interfaces (e.g. `presencePulseClient`,
  `presencePulseDeviceSource`, `sendMessageFn`, `subscribePresenceFn`, `submitWebhookFn`, `getChatwootClientFn`)
  and injectable `now()`/`sleep()` so tests are deterministic without real timers or network.
- **Serial globals** — tests touching config/package globals/worker state restore with `defer` and avoid parallelism.

## Conventions to follow

- **Adding a message type:** touch `domains/send/` → `usecase/send.go` → `ui/rest/send.go` (+ optional `ui/mcp/`). REST is primary; MCP support is selective.
- **Adding a REST endpoint:** handler (parse) → usecase (validate/execute) → domain (own DTO/interface). Device-scoped routes must call `whatsapp.ContextWithDevice(c.UserContext(), getDeviceFromCtx(c))`.
- **Adding an MCP tool:** register in `Add*Tools`; resolve device via `helpers.ContextWithDefaultDevice`.
- **Handling a WhatsApp event:** add `event_<thing>.go` + register the concrete event in `event_handler.go`.
- **Adding a chat-storage method:** update `domains/chatstorage/interfaces.go` **+** `sqlite_repository.go` **+**
  `chatstorage_wrapper.go` together (the wrapper enforces device scoping).
- **Adding a DB migration:** **append only** to `getMigrations()` — never insert mid-list.
- **Optional boolean filters** use `*bool` so `nil` means "not provided".
- **Errors:** surface business failures via `pkg/error` sentinel errors (closed set); adapters map them to HTTP/protocol status.

## Anti-patterns to avoid

- Querying chats/messages **without `device_id` scoping** for user-facing flows.
- Using `instance.ID()` as the `device_id` after login — use `client.Store.ID.ToNonAD().String()`.
- Using raw `@lid` JIDs for DB lookups — normalize with `NormalizeJIDFromLID()` first.
- Removing the `evt.Sender.Device != 0` receipt check (prevents duplicate webhooks from linked devices).
- Inserting migrations mid-`getMigrations()`.
- Treating Chatwoot direct-Postgres import as the live forwarding path — it is history-only.
- Running REST and MCP in one process against the same whatsmeow state.
