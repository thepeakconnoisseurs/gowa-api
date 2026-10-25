# Project Overview — GoWA (Go WhatsApp Web Multi-Device)

> Generated: 2026-06-17 · Scan: exhaustive · Source commit lineage: `main`

## What this project is

**GoWA** (`github.com/aldinokemal/go-whatsapp-web-multidevice`, app version **v8.8.0**) is a self-hostable
**WhatsApp Web multi-device API server** written in Go. It bridges the unofficial
[`whatsmeow`](https://github.com/tulir/whatsmeow) WhatsApp client library to three programmatic surfaces so
other software — internal services, automation tools (n8n), or AI agents — can send/receive WhatsApp messages
without a phone tethered to the process:

1. **HTTP REST API** — the primary surface (~77 routes): send every message type, manage groups/newsletters,
   query chat history, manage multiple linked WhatsApp accounts ("devices").
2. **MCP (Model Context Protocol) server** — an SSE server exposing **29 tools** so AI agents (e.g. Cursor) can
   drive WhatsApp through a standardized protocol.
3. **Embedded Vue 3 web UI** + **WebSocket** event stream — a built-in dashboard for login (QR / pair code),
   send, and live event observation.

It also ships a deep **Chatwoot** integration: two-way message sync, history backfill (REST or direct-Postgres),
and read/delete propagation — turning GoWA into a WhatsApp backend for a Chatwoot helpdesk.

> ⚠️ This project is unofficial and not affiliated with WhatsApp. Use the official WhatsApp Business API for
> production compliance. REST and MCP **cannot run together in one process** against the same whatsmeow state
> (a whatsmeow library limitation); run one mode per process.

## Executive summary

| Aspect | Detail |
|---|---|
| Type | Single-process backend service (monolith), one Go module |
| Language | Go 1.25.5 |
| Module root | `src/` (Go commands run from `src/`, **not** the repo root) |
| Transport | Fiber v2 (HTTP/REST/WebSocket) + `mcp-go` SSE |
| WhatsApp engine | `go.mau.fi/whatsmeow` (multi-device protocol) |
| Storage | SQLite by default (CGO `mattn/go-sqlite3`, or `modernc.org/sqlite` under `-tags purego`); optional separate keys DB; optional Postgres for Chatwoot history import |
| Config | Cobra flags > env vars (Viper) > `.env` > compiled defaults — all held as mutable package globals |
| Multi-device | First-class: multiple WhatsApp accounts managed per process, each request scoped via `X-Device-Id` / `device_id` |
| External runtime deps | `ffmpeg`, `ffprobe`, `libwebp` (`cwebp`/`webpmux`/`dwebp`), optionally `poppler-utils` (`pdftoppm`) + ImageMagick (`convert`) for PDF thumbnails |

## Technology stack

| Category | Technology | Version | Justification |
|---|---|---|---|
| Language | Go | 1.25.5 | `go.mod` |
| HTTP framework | `gofiber/fiber/v2` | 2.52.13 | REST API, routing, static/embedded UI |
| Template engine | `gofiber/template/html/v2` | 2.1.3 | Renders the embedded Vue index page |
| WebSocket | `gofiber/websocket/v2` | 2.2.1 | Live event broadcast (`/ws`) |
| WhatsApp protocol | `go.mau.fi/whatsmeow` | latest (`20260611…`) | Multi-device WhatsApp client |
| Signal crypto | `go.mau.fi/libsignal` | 0.2.2 | E2E encryption backing whatsmeow |
| MCP | `mark3labs/mcp-go` | 0.54.0 | Model Context Protocol SSE server |
| CLI / config | `spf13/cobra` + `spf13/viper` | 1.10.2 / 1.21.0 | Subcommands (`rest`, `mcp`), flag/env config |
| Validation | `go-ozzo/ozzo-validation/v4` | 4.3.0 | Request DTO validation |
| SQLite (CGO) | `mattn/go-sqlite3` | 1.14.44 | Default chat/session storage driver |
| SQLite (purego) | `modernc.org/sqlite` | 1.50.1 | CGO-free build (`-tags purego`, e.g. Raspberry Pi) |
| Postgres | `lib/pq` | 1.12.3 | Direct Chatwoot history import |
| Logging | `sirupsen/logrus` | 1.9.4 | Structured logging |
| Fast HTTP | `valyala/fasthttp` | 1.71.0 | Fiber engine |
| IDs | `google/uuid` | 1.6.0 | Device IDs, media filenames |
| Imaging | `disintegration/imaging`, `golang.org/x/image` | 1.6.2 / 0.41.0 | Image resize/thumbnail/sticker conversion |
| HTML parsing | `PuerkitoBio/goquery` | 1.12.0 | OG link-preview scraping |
| Humanize | `dustin/go-humanize` | 1.0.1 | File-size display in UI |
| QR codes | `skip2/go-qrcode` | — | WhatsApp QR login |
| Protobuf | `google.golang.org/protobuf` | 1.36.11 | WhatsApp message protos |
| Testing | `stretchr/testify`, `DATA-DOG/go-sqlmock` | 1.11.1 / 1.5.2 | Table-driven tests, mocked SQL |

## Architecture classification

- **Repository type:** monolith (single cohesive codebase, one Go module).
- **Architecture pattern:** **Clean / Hexagonal layering** with strict dependency direction
  `cmd → ui → usecase → domains + infrastructure`. See [architecture.md](./architecture.md).
- **State model:** mutable package globals for the object graph (no DI container) — wired once in `cmd.initApp()`.

```
src/
├── main.go              # //go:embed views, then cmd.Execute
├── cmd/                 # Cobra root + rest/mcp subcommands + global app wiring
├── config/              # Package-global config bound from flags/env
├── domains/             # DTOs + interfaces (no business logic) — the hexagon core
├── usecase/             # Business orchestration (implements domain interfaces)
├── validations/         # ozzo-validation rules (table-tested)
├── ui/                  # Adapters: rest/ (Fiber), mcp/ (MCP SSE), websocket/
├── infrastructure/      # whatsmeow wrapper, SQLite repo, Chatwoot client + pgimport
├── pkg/                 # Shared: error types, sqlite driver select, utils
├── views/               # Embedded Vue 3 (CDN) plain-JS UI
├── statics/             # Runtime: media, QR codes, send items
└── storages/            # Runtime: SQLite DBs, history dumps
```

## Documentation map

| Document | Purpose |
|---|---|
| [index.md](./index.md) | **Master index — start here** |
| [architecture.md](./architecture.md) | Layered architecture, data flow, conventions, testing |
| [api-contracts-gowa.md](./api-contracts-gowa.md) | Every REST endpoint + MCP tool + response envelope |
| [data-models-gowa.md](./data-models-gowa.md) | SQLite schema (7 tables, 29 migrations) + domain DTO summary |
| [source-tree-analysis.md](./source-tree-analysis.md) | Annotated directory tree with critical folders |
| [component-inventory.md](./component-inventory.md) | Internal module/component map |
| [development-guide.md](./development-guide.md) | Prerequisites, local setup, build, test commands |
| [deployment-guide.md](./deployment-guide.md) | Docker, docker-compose, CI/CD, env config |
| **Pre-existing (authoritative):** | |
| [openapi.yaml](./openapi.yaml) | Machine-readable OpenAPI spec for the REST API |
| [webhook-payload.md](./webhook-payload.md) | Outbound webhook event schemas + HMAC signing |
| [chatwoot.md](./chatwoot.md) | Chatwoot integration guide |

## Getting started (60 seconds)

```bash
# From the repo root — Go module lives in src/
cd src
cp .env.example .env          # then edit .env (optional)
go run . rest                 # REST API + UI on http://localhost:3000
# — or —
go run . mcp                  # MCP SSE server on http://localhost:8080
```

Prefer Docker (no Go/FFmpeg install needed):

```bash
docker compose up -d --build  # exposes 127.0.0.1:3500 → container:3000
```

Open `http://localhost:3000`, scan the QR with your phone, and start calling the API. Full setup, flags, and
testing in [development-guide.md](./development-guide.md).
