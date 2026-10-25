# Component Inventory — GoWA (gowa backend)

> Generated: 2026-06-17 · Scan: exhaustive
> Project type is `backend` (no formal UI component framework), so this inventory catalogs the **internal Go
> modules/components** that make up the system, plus the embedded Vue UI modules. Use this as a navigation map for
> AI-assisted work — each entry says what it is and where to find it.

## Key structural components (Go)

The load-bearing types/functions, grouped by layer. File paths are relative to `src/`.

### Application wiring & lifecycle (`cmd/`, `config/`)

| Component | Kind | Location | Role |
|---|---|---|---|
| `cmd.Execute` | function | `cmd/root.go` | Stores embedded views, runs Cobra root |
| `initApp` | function | `cmd/root.go` | Wires the whole object graph (globals, not DI) |
| `initEnvConfig` | function | `cmd/root.go` | Viper env overlay onto config globals |
| `helpers.SetAutoConnectAfterBooting` | function | `cmd/helpers.go` | Boot-time auto-reconnect |
| `helpers.startPresencePulseSchedulerIfEnabled` | function | `cmd/helpers.go` | `sync.Once` pulse starter |
| `config.*` | package globals | `config/settings.go` | All tunables (App/Mcp/Paths/DB/WhatsApp/ChatStorage/Chatwoot) |

### WhatsApp engine (`infrastructure/whatsapp/`)

| Component | Kind | Location | Role |
|---|---|---|---|
| `DeviceManager` | struct | `device_manager.go` | Registry of active devices; persist/load/create/purge; `ResolveDevice` |
| `DeviceInstance` | struct | `device_instance.go` | Per-account client + state + scoped repo |
| `handler` | function | `event_handler.go` | **Single** event dispatcher (type-switch) |
| `InitWaDB` / `InitWaCLI` | functions | `init.go` | Build whatsmeow store container + primary client |
| `NormalizeJIDFromLID` | function | `jid_utils.go` | `@lid` → phone JID normalization seam |
| `deviceChatStorage` | wrapper | `chatstorage_wrapper.go` | Device-scoped repo decorator |
| `submitWebhook` | function | `webhook.go` | HMAC-signed HTTP POST worker (5 retries) |
| `forwardPayloadToConfiguredWebhooks` | function | `webhook_forward.go` | Webhook + Chatwoot fan-out entry point |
| `StartChatwootForwardRetryWorker` | function | `webhook_forward.go` | Durable retry worker (30s tick) |
| `StartPresencePulseScheduler` | function | `presence_pulse.go` | Periodic available↔unavailable cycle |
| `SendMessageWithReachoutRetry` | function | `send_retry.go` | Send + single retry on WA error 463 |
| `handleMessage/Receipt/CallOffer/…` | functions | `event_*.go` | Per-event-type handlers |
| `ContextWithDevice`/`DeviceFromContext`/`ClientFromContext` | functions | `context_device.go` | Context-based device plumbing |

### Storage (`infrastructure/chatstorage/`, `domains/chatstorage/`)

| Component | Kind | Location | Role |
|---|---|---|---|
| `SQLiteRepository` | struct | `sqlite_repository.go` | Implements `IChatStorageRepository`; all 7 tables |
| `getMigrations` | function | `sqlite_repository.go` | 29 ordered inline SQL migrations (append-only) |
| `IChatStorageRepository` | interface | `domains/chatstorage/interfaces.go` | Storage contract |
| `InitializeSchema` | method | `sqlite_repository.go` | Runs pending migrations |

### Chatwoot integration (`infrastructure/chatwoot/`)

| Component | Kind | Location | Role |
|---|---|---|---|
| `Client` | struct | `client.go` | Chatwoot REST client (contacts/conversations/messages) |
| `GetDefaultClient` | function | `client.go` | `sync.Once` singleton |
| `EnsureInbox` | function | `provision.go` | Auto-provision API-channel inbox |
| `SyncService` | struct | `sync.go` | History sync (REST or pgimport); `TriggerAutoSync` |
| `pgimport.Importer` | struct | `pgimport/conn.go` | Direct-Postgres history importer |
| `MarkMessageAsSent`/`IsMessageSentByUs` | functions | `client.go` | Echo-loop prevention (5-min TTL `sync.Map`) |

### Use cases (`usecase/`) — the business boundary

One struct per domain, each implementing the matching `IXxxUsecase` interface: `serviceApp`, `serviceChat`,
`serviceDevice`, `serviceGroup`, `serviceMessage`, `serviceNewsletter`, `serviceSend`, `serviceUser`. All follow
the **validate → resolve device/client from context → execute → shape response** spine.

### Adapters (`ui/`)

| Component | Kind | Location | Role |
|---|---|---|---|
| `restServer` | function | `cmd/rest.go` | Fiber app + middleware + routes |
| `middleware.DeviceMiddleware` | middleware | `ui/rest/middleware/device.go` | Multi-device scoping |
| `middleware.Recovery` / `RequestTimeout` / `BasicAuth` | middleware | `ui/rest/middleware/` | Cross-cutting |
| `InitMcpSend/Query/App/Group` (→ `Add*Tools`) | functions | `ui/mcp/*.go` | Register the 29 MCP tools |
| `helpers.ContextWithDefaultDevice` | helper | `ui/mcp/helpers/context.go` | MCP default-device injection |
| `RunHub` / `Broadcast` | hub | `ui/websocket/websocket.go` | WebSocket fan-out |

### Shared (`pkg/`)

| Component | Kind | Location | Role |
|---|---|---|---|
| `GenericError` interface + concrete errors | types | `pkg/error/*` | Typed errors with stable code + HTTP status |
| `sqlite.DriverName` / `FormatChatStorageURI` | symbols | `pkg/sqlite/sqlite_{cgo,purego}.go` | Build-tag driver selection |
| `utils.*` | helpers | `pkg/utils/*` | Phone/JID, image, media extract, markdown, response shaping |

## Sentinel errors (closed set — `pkg/error`)

| Sentinel | Code | HTTP | Meaning |
|---|---|---|---|
| `ErrAlreadyLoggedIn` | `ALREADY_LOGGED_IN` | 400 | Device already connected |
| `ErrWaCLI` | `INVALID_WA_CLI` | 500 | No whatsapp client in context |
| `ErrNotConnected` / `ErrNotLoggedIn` | — | — | Session state |
| `ErrReconnect` | — | — | Reconnect failed |
| `ErrQrChannel` | `QR_CHANNEL_ERROR` | 500 | QR flow failure |
| `ErrSessionSaved` | `SESSION_SAVED_ERROR` | 500 | Pair/QR store conflict |
| `ErrInvalidJID` / `ErrUserNotRegistered` | `INVALID_JID` | 400 | JID/account invalid |
| `ValidationError` | `VALIDATION_ERROR` | 400 | Request validation |
| `ContextError` | `CONTEXT_ERROR` | 408 | Deadline/deadline-exceeded |
| `ErrWaReachoutTimelock` | `WA_REACHOUT_TIMELOCK` | 429 | WA error 463 (cold contact / privacy token) |

## Embedded Vue UI (`src/views/`)

A lightweight single-page UI served embedded via `//go:embed`. It is **plain ES-module JavaScript** using Vue 3
from CDN + Fomantic UI modals/toasts, with custom delimiters `[[ ]]` (to avoid Go template clashes). There are
**no `.vue` single-file components**.

| Area | Location | Content |
|---|---|---|
| Shell | `views/index.html` | Landing page template; rendered with `AppHost`, `AppVersion`, `AppBasePath`, `BasicAuthToken`, size limits |
| Assets | `views/assets/` | `gowa.svg` logo, CSS |
| Modules | `views/components/` | 49 `.js` modules (e.g. `Send*.js`, login, devices, groups) + `generic/` shared widgets |
| README | `views/components/README.md` | Authoring notes for the UI |

The UI is an **optional convenience surface** — the REST API and MCP server are the programmatic contracts. UI
changes are isolated to `views/` and the index template in `cmd/rest.go`.
