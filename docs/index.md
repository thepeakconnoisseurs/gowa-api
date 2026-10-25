# GoWA Documentation Index

> **Primary entry point for AI-assisted development.** Point PRD / planning workflows here.
> Project: **GoWA** — `github.com/aldinokemal/go-whatsapp-web-multidevice` · Go 1.25.5 · app version **v8.8.0**
> Generated: 2026-06-17 · Scan: exhaustive · Output language: English

---

## Project Overview

- **Type:** Monolith backend (single Go module, one cohesive codebase)
- **Primary language:** Go 1.25.5
- **Architecture:** Clean / hexagonal layering (`cmd → ui → usecase → domains + infrastructure`); mutable package globals, no DI container
- **What it does:** A self-hostable **WhatsApp Web multi-device API server** exposing a **REST API** (~77 routes), an **MCP SSE server** (29 tools), and an embedded **Vue UI + WebSocket** stream over the `whatsmeow` library — with deep **Chatwoot** integration (two-way sync, history backfill via REST or direct-Postgres).

### Quick reference

- **Tech stack:** Go, Fiber v2, whatsmeow, mcp-go, cobra+viper, ozzo-validation, SQLite (`go-sqlite3` CGO / `modernc.org/sqlite` purego), lib/pq (Chatwoot PG import), logrus. External runtime deps: **FFmpeg**, **libwebp** (optionally poppler-utils).
- **Entry point:** `src/main.go` → `cmd.Execute` → Cobra `rest` or `mcp` subcommand → `initApp()` wires globals.
- **Go module root:** **`src/`** (run all Go commands there; repo root is not the module root).
- **Storage:** `chatstorage.db` (GoWA read-model, 7 tables, 29 inline migrations) + `whatsapp.db` (whatsmeow sessions) + optional keys DB + optional Chatwoot Postgres.
- **Multi-device:** first-class; each request scoped by `X-Device-Id` / `?device_id=` (MCP uses the default/only device).

### Run in 60 seconds

```bash
cd src && go run . rest      # REST API + UI → http://localhost:3000
# — or —
cd src && go run . mcp       # MCP SSE → http://localhost:8080/sse
# — or Docker —
docker compose up -d --build # → http://localhost:3500
```

> ⚠️ Unofficial, not affiliated with WhatsApp. REST and MCP **cannot share one process** (whatsmeow limitation).

---

## Generated Documentation

| Document | What it covers |
|---|---|
| 🏠 **[Project Overview](./project-overview.md)** | Purpose, executive summary, full tech-stack table, repo structure, doc map |
| 🏛️ **[Architecture](./architecture.md)** | Layered architecture, data/event flow, conventions, anti-patterns, testing |
| 🔌 **[API Contracts](./api-contracts-gowa.md)** | Every REST endpoint (77) + MCP tools (29) + WebSocket + response envelope + auth |
| 🗄️ **[Data Models](./data-models-gowa.md)** | SQLite schema (7 tables), 29 migrations, repository contract, domain DTO summary |
| 🌳 **[Source Tree Analysis](./source-tree-analysis.md)** | Annotated directory tree, entry points, critical folders |
| 🧩 **[Component Inventory](./component-inventory.md)** | Internal Go module/type map + sentinel errors + embedded Vue UI |
| 🛠️ **[Development Guide](./development-guide.md)** | Prerequisites, setup, commands, conventions, testing |
| 🚢 **[Deployment Guide](./deployment-guide.md)** | Docker, docker-compose, full flag/env config, CI/CD |

---

## Pre-existing Documentation (authoritative, author-maintained)

| Document | What it covers |
|---|---|
| 📄 **[openapi.yaml](./openapi.yaml)** | Machine-readable OpenAPI 3 spec for the REST API (~4,500 lines) — use for client generation |
| 🔔 **[webhook-payload.md](./webhook-payload.md)** | Outbound webhook event schemas, HMAC-SHA256 signing, integration examples |
| 💬 **[chatwoot.md](./chatwoot.md)** | Chatwoot integration guide (REST sync + direct-Postgres import) |
| 🤖 **[../AGENTS.md](../AGENTS.md)** | AI knowledge base — code map, conventions, anti-patterns, "where to look" table (at repo root) |
| 📘 **[../readme.md](../readme.md)** | User-facing README — feature list, full endpoint table, env vars, Docker usage |
| 📦 **[sdk/config.yaml](./sdk/config.yaml)** | openapi-generator SDK config |

---

## Navigation by task

| If you want to… | Read this |
|---|---|
| Understand the system end-to-end | [Architecture](./architecture.md) → [Project Overview](./project-overview.md) |
| Call a REST endpoint | [API Contracts](./api-contracts-gowa.md) (+ [openapi.yaml](./openapi.yaml) for exact schemas) |
| Use the MCP server / tools | [API Contracts → MCP](./api-contracts-gowa.md#mcp-model-context-protocol-server) |
| Add a new message type | `domains/send/` → `usecase/send.go` → `ui/rest/send.go` (+ optional `ui/mcp/`) — see [Architecture → Conventions](./architecture.md#conventions-to-follow) |
| Add a REST endpoint | handler (`ui/rest/`) → usecase → domain DTO — see [Architecture](./architecture.md) |
| Modify the DB schema | [Data Models](./data-models-gowa.md) — **append-only** migrations in `sqlite_repository.go::getMigrations()` |
| Handle a new WhatsApp event | `infrastructure/whatsapp/event_*.go` + register in `event_handler.go` — see [Component Inventory](./component-inventory.md) |
| Configure / deploy | [Deployment Guide](./deployment-guide.md) |
| Set up local dev / run tests | [Development Guide](./development-guide.md) |
| Integrate Chatwoot | [chatwoot.md](./chatwoot.md) + [Architecture → Chatwoot](./architecture.md#chatwoot-integration-architecture) |
| Receive WhatsApp events server-side | [webhook-payload.md](./webhook-payload.md) |

---

## Generated artifacts

- This documentation set lives in `docs/` (the `project_knowledge` directory).
- Workflow state: [`project-scan-report.json`](./project-scan-report.json) (records scan mode, level, completed steps).
- To refresh: re-run the **document-project** workflow — it will offer a full re-scan or a deep-dive into a specific area.

**Brownfield PRD:** when planning new features, run the PRD workflow and provide **this `index.md`** as the project context input.
