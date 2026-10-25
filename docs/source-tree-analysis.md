# Source Tree Analysis — GoWA (Go WhatsApp Web Multi-Device)

> Generated: 2026-06-17 · Scan: exhaustive · Annotated directory tree with critical folders and entry points.
> Go module root is **`src/`** (run all Go commands there). Repo root holds Docker, docs, CI, gallery.

## Repository layout

```
go-whatsapp-web-multidevice/          # repo root (NOT the Go module root)
├── readme.md                         # User-facing README (full API table, env vars, Docker usage)
├── AGENTS.md                         # AI knowledge base (code map, conventions, anti-patterns)
├── LICENCE.txt
├── docker-compose.yml                # Dev/ops compose: builds gowa-api, 127.0.0.1:3500:3000
├── .gitignore  .dockerignore
│
├── docker/                           # 🐳 Container build
│   ├── golang.Dockerfile             #   Two-stage Alpine: builder(CGO musl) → runtime(gowauser non-root)
│   └── entrypoint.sh                 #   chown runtime volumes, then su-exec drop privileges
│
├── docs/                             # 📚 Documentation (project_knowledge)
│   ├── index.md                      #   ◀ Master index (this documentation set)            [generated]
│   ├── openapi.yaml                  #   Authoritative OpenAPI 3 spec (~4.500 lines)
│   ├── webhook-payload.md            #   Outbound webhook event schemas + HMAC
│   ├── chatwoot.md                   #   Chatwoot integration guide
│   ├── agent-progress.md             #   Author's progress notes
│   ├── sdk/config.yaml               #   SDK generator config (openapi-generator)
│   └── project-scan-report.json      #   This workflow's state file                        [generated]
│
├── gallery/                          # 🖼️ Static screenshots for the README
│
├── .github/
│   ├── workflows/
│   │   ├── build-docker-image.yaml   #   Multi-arch (amd/arm/armv7) + manifest merge
│   │   ├── release.yml               #   GoReleaser binaries (tag-guarded)
│   │   └── set-latest-tag.yaml       #   Manual :latest promotion
│   ├── pull_request_template.md  ISSUE_TEMPLATE/  FUNDING.yml
│
└── src/                              # ◀ GO MODULE ROOT — module github.com/aldinokemal/go-whatsapp-web-multidevice
    ├── main.go                       # ENTRY: //go:embed views, then cmd.Execute
    ├── go.mod  go.sum                # Go 1.25.5, deps (whatsmeow, fiber, mcp-go, cobra/viper…)
    ├── .env.example  .env            # Environment config template / local
    ├── .air.toml                     # Hot-reload (Air) — excludes statics/storages
    │
    ├── cmd/                          # 🧩 Cobra CLI + global app wiring
    │   ├── root.go                   #   rootCmd, init() bootstrap, initApp(), initFlags(), initEnvConfig()
    │   ├── rest.go                   #   `rest` subcommand (self-registers via init()) → restServer()
    │   ├── mcp.go                    #   `mcp` subcommand → mcpServer() (mcp-go SSE)
    │   └── helpers.go                #   getValidWhatsAppClient, auto-reconnect checker, presence-pulse starter
    │
    ├── config/                       # ⚙️ Mutable package globals bound from flags/env
    │   └── settings.go               #   App*/Mcp/Paths/DB/WhatsApp*/ChatStorage*/Chatwoot* globals; AppVersion v8.8.0
    │
    ├── domains/                      # 📐 DTOs + interfaces (NO business logic) — hexagon core
    │   ├── app/                      #   session lifecycle DTOs + IAppUsecase
    │   ├── chat/                     #   list-chats/messages + pin/archive/disappearing DTOs + IChatUsecase
    │   ├── chatstorage/              #   DB-mapped entities (Chat/Message/Reaction/…) + IChatStorageRepository
    │   ├── device/                   #   Device entity, DeviceState enum + IDeviceUsecase
    │   ├── group/                    #   group/participant DTOs + IGroup{Management,Participants,Settings}
    │   ├── message/                  #   revoke/delete/react/edit/read/star/download DTOs + IMessageUsecase
    │   ├── newsletter/               #   unfollow DTO + INewsletterUsecase
    │   ├── send/                     #   ◀ LARGEST — 15 files, all outbound message DTOs + ISendUsecase
    │   │   ├── base.go               #     BaseRequest (Phone/Duration/IsForwarded) — embedded by most
    │   │   ├── interfaces.go         #     IText/IMedia/IInteraction/IPresenceSender → ISendUsecase
    │   │   └── text/image/video/audio/file/sticker/contact/link/location/poll/presence/chat_presence.go
    │   └── user/                     #   info/avatar/privacy/listings DTOs + IUserUsecase
    │
    ├── usecase/                      # 🧠 Business orchestration (implements domain interfaces)
    │   └── app/chat/device/group/message/newsletter/send/user.go  # validate → resolve device → execute → shape
    │
    ├── validations/                  # ✅ ozzo-validation rules (table-tested)
    │   └── app/chat/group/message/newsletter/send/user_validation.go
    │
    ├── ui/                           # 🌐 Adapters (transport-specific, call usecases)
    │   ├── rest/                     #   ◀ PRIMARY: Fiber REST API (~77 routes)
    │   │   ├── app/chat/device/group/message/newsletter/send/user/chatwoot.go  # handlers
    │   │   ├── helpers/common.go     #     response/multipart helpers
    │   │   └── middleware/           #     basicauth.go, device.go (device scoping), recovery.go, timeout.go
    │   ├── mcp/                      #   MCP SSE tools (29 tools): app/send/query/group + helpers/context.go
    │   └── websocket/                #   /ws broadcast hub (RunHub, BroadcastMessage envelope)
    │
    ├── infrastructure/               # 🔌 Concrete implementations
    │   ├── whatsapp/                 #   ◀ whatsmeow wrapper (27 files)
    │   │   ├── init.go database.go logger.go           #   bootstrap: InitWaDB/InitWaCLI, filteredLogger
    │   │   ├── device_manager.go device_instance.go    #   DeviceManager registry + DeviceInstance per-account
    │   │   ├── context_device.go                      #   context-based device/client plumbing
    │   │   ├── event_handler.go                       #   ◀ single event dispatcher (type-switch)
    │   │   ├── event_message(_handler).go event_receipt.go event_call.go event_chat_presence.go
    │   │   ├── event_delete.go event_group.go event_label.go event_newsletter.go event_archive.go
    │   │   ├── webhook.go webhook_forward.go          #   outbound webhook fan-out + Chatwoot forward
    │   │   ├── presence_pulse.go                      #   StartPresencePulseScheduler (available↔unavailable)
    │   │   ├── history_sync.go auto_reply.go send_retry.go key_cache.go
    │   │   ├── jid_utils.go                           #   NormalizeJIDFromLID (@lid → phone)
    │   │   └── chatstorage_wrapper.go                 #   device-scoped repo decorator
    │   ├── chatstorage/              #   SQLite repository
    │   │   └── sqlite_repository.go  #   ◀ IChatStorageRepository + 7 tables + 29 inline migrations
    │   └── chatwoot/                 #   Chatwoot integration
    │       ├── client.go provision.go sync.go sync_types.go types.go  # REST sync path
    │       └── pgimport/             #   conn.go identity.go writer.go — direct-Postgres history import
    │
    ├── pkg/                          # 🛠️ Shared utilities
    │   ├── error/                    #   typed errors (package name "error"; alias as pkgError)
    │   ├── sqlite/                   #   sqlite_cgo.go / sqlite_purego.go (build-tag driver select)
    │   └── utils/                    #   phone/image/environment/response/whatsapp/chatwoot/general helpers
    │
    ├── views/                        # 🖥️ Embedded Vue 3 UI (plain JS modules, CDN Vue, no .vue SFCs)
    │   ├── index.html                #   landing page template
    │   ├── assets/                   #   gowa.svg + CSS
    │   └── components/               #   49 .js modules (Send*.js, generic/) + README.md
    │
    ├── statics/                      # 📁 Runtime artifacts (gitignored content)
    │   ├── media/                    #   downloaded/incoming media
    │   ├── qrcode/                   #   login QR PNGs (ephemeral)
    │   └── senditems/                #   processed outbound media
    │
    └── storages/                     # 💾 Runtime SQLite DBs + history dumps (gitignored)
        ├── whatsapp.db  whatsapp-keys.db  chatstorage.db
        └── history-*.json
```

## Entry points

| Entry | Location | Role |
|---|---|---|
| Process entry | `src/main.go` | `//go:embed views`, calls `cmd.Execute(...)` |
| CLI dispatch | `src/cmd/root.go` | Cobra root; `init()` → load `.env`, set UTC, define flags, `OnInitialize(initEnvConfig, initApp)` |
| App wiring | `src/cmd/root.go` `initApp()` | Creates dirs, DBs, whatsapp client, device manager, repos, 8 usecases |
| REST bootstrap | `src/cmd/rest.go` `restServer()` | Builds Fiber app, middleware chain, route groups, `/health`, graceful shutdown |
| MCP bootstrap | `src/cmd/mcp.go` `mcpServer()` | Builds mcp-go SSE server, registers 29 tools, starts presence/reconnect helpers |
| WhatsApp engine | `src/infrastructure/whatsapp/init.go` | `InitWaDB`/`InitWaCLI` build the whatsmeow client(s) |

## Critical folders

| Folder | Why it matters |
|---|---|
| `src/domains/send/` | The outbound-message contract surface — touch here for any new message type |
| `src/usecase/` | The single business boundary shared by REST + MCP |
| `src/infrastructure/whatsapp/` | All whatsmeow mechanics: device registry, events, webhooks, presence |
| `src/infrastructure/chatstorage/sqlite_repository.go` | Schema + migrations (the data backbone) |
| `src/infrastructure/chatwoot/` (+`pgimport/`) | The two Chatwoot backends (REST live + PG history) |
| `src/ui/rest/` + `src/ui/mcp/` | The two adapters — REST is primary, MCP is a curated subset |
| `src/config/settings.go` | Every tunable lives here as a package global |

## Build-tag & runtime paths

- **CGO build** (default): `github.com/mattn/go-sqlite3`. **purego build** (`-tags purego`): `modernc.org/sqlite`
  (CGO-free, for Raspberry Pi / static cross-compile).
- **Local runs** start from `src/` → runtime paths `src/storages`, `src/statics`.
- **Docker runs** mount root `./storages` + `./statics` → `/app/storages`, `/app/statics` (entrypoint chowns them).
- `src/.air.toml` excludes `statics`/`storages` from hot-reload watching.
