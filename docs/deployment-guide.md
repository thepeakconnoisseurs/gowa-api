# Deployment Guide — GoWA (Go WhatsApp Web Multi-Device)

> Generated: 2026-06-17 · Scan: exhaustive · Source: `docker/golang.Dockerfile`, `docker/entrypoint.sh`,
> `docker-compose.yml`, `.github/workflows/*`, `src/config/settings.go`.

## Deployment options

1. **Docker / Docker Compose** (recommended — bundles FFmpeg + libwebp, no Go install needed).
2. **Prebuilt binary** from GitHub Releases (GoReleaser-built; you still need FFmpeg + libwebp on the host).
3. **Build from source** — see [development-guide.md](./development-guide.md).

## Docker

### Image

Two-stage `docker/golang.Dockerfile`:

- **Builder** — `golang:1.25-alpine3.23` + CGO toolchain (`gcc musl-dev gcompat`); caches `go mod download`;
  builds `go build -ldflags="-w -s" -o /app/whatsapp`.
- **Runtime** — `alpine:3.23` + `ffmpeg libwebp-tools poppler-utils tzdata su-exec`; non-root user
  **`gowauser`** (uid `20001`, group `gowa` gid `20000` — distinct ids because BusyBox `adduser` rejects equal
  uid/gid when the gid exists). `ENV TZ=UTC`, `WORKDIR /app`, binary + entrypoint copied and chowned.

**Entrypoint** (`docker/entrypoint.sh`): runs as `root` only long enough to `chown` the runtime dirs
(`/app/storages`, `/app/statics{,/qrcode,/senditems,/media}`) to `gowauser` — host bind mounts are typically
root-owned but SQLite needs write access for DB + WAL — then `exec su-exec gowauser /app/whatsapp "$@"` drops
privileges. Default `CMD ["rest"]`.

Prebuilt images:
- Docker Hub: `aldinokemal2104/go-whatsapp-web-multidevice`
- GHCR: `ghcr.io/aldinokemal/go-whatsapp-web-multidevice`

### docker-compose (this repo)

The repo's `docker-compose.yml` builds and runs a single service:

```yaml
services:
  whatsapp_go:
    container_name: gowa-api
    build:
      context: .
      dockerfile: ./docker/golang.Dockerfile
      tags: ["gowa-api:latest"]
    restart: "on-failure"
    ports:
      - "127.0.0.1:3500:3000"     # host loopback only → container 3000
    env_file: [src/.env]
    volumes:
      - ./storages:/app/storages  # persist WhatsApp + chat DBs
      - ./statics:/app/statics    # media, QR, send items
    networks: [n8n-tpc, gowa-api]
networks:
  n8n-tpc: { external: true }
  gowa-api: { driver: bridge }
```

```bash
docker compose up -d --build       # → http://localhost:3500
```

> The local compose intentionally binds to `127.0.0.1:3500` (loopback only) and joins an external `n8n-tpc`
> network — tailored to this deployment. For a public deployment, front it with a reverse proxy (TLS, auth) and
> expose accordingly.

### Production Docker run (upstream examples)

Using Docker Hub:
```bash
docker run --detach --publish=3000:3000 --name=whatsapp --restart=always \
  --volume=$(docker volume create --name=whatsapp):/app/storages \
  aldinokemal2104/go-whatsapp-web-multidevice rest --autoreply="Don't reply please"
```
Using GHCR: swap the image for `ghcr.io/aldinokemal/go-whatsapp-web-multidevice`.

### ARM / Raspberry Pi

Use the CGO-free purego build or the prebuilt ARM images (`-arm`, `-armv7`). From source on a non-ARM host:

```bash
CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7 go build -tags purego -o whatsapp-armv7
```

## Configuration (flags & environment)

Priority: **CLI flags > env vars (Viper) > `.env` > compiled defaults.** Most flags map 1:1 to an env var
(snake_case, e.g. `--port` ↔ `APP_PORT`). **MCP `--port/--host` are local to the `mcp` subcommand** and do not
read `APP_PORT`. A few Chatwoot settings are **env-only** (`CHATWOOT_URL`, `CHATWOOT_API_TOKEN`,
`CHATWOOT_ACCOUNT_ID`, `CHATWOOT_INBOX_ID`) and `ChatStorageURI`/`EnableWAL`/`EnableForeignKeys` are compile-time only.

### Application

| Flag | Env | Default |
|---|---|---|
| `--port` / `-p` | `APP_PORT` | `3000` |
| `--host` / `-H` | `APP_HOST` | `0.0.0.0` |
| `--debug` / `-d` | `APP_DEBUG` | `false` |
| `--os` | `APP_OS` | `GOWA` |
| `--basic-auth` / `-b` | `APP_BASIC_AUTH` | — (`user:secret,user2:secret2`) |
| `--base-path` | `APP_BASE_PATH` | — (e.g. `/gowa`) |
| `--trusted-proxies` | `APP_TRUSTED_PROXIES` | — (CIDRs) |

### Database

| Flag | Env | Default |
|---|---|---|
| `--db-uri` | `DB_URI` | `file:storages/whatsapp.db` |
| `--db-keys-uri` | `DB_KEYS_URI` | — (leave blank → uses `DB_URI`; avoid in-memory in prod — privacy tokens must persist) |

### WhatsApp behavior

| Flag | Env | Default |
|---|---|---|
| `--autoreply` | `WHATSAPP_AUTO_REPLY` | — |
| `--auto-mark-read` | `WHATSAPP_AUTO_MARK_READ` | `false` |
| `--auto-download-media` | `WHATSAPP_AUTO_DOWNLOAD_MEDIA` | `true` |
| `--auto-reject-call` | `WHATSAPP_AUTO_REJECT_CALL` | `false` |
| `--account-validation` | `WHATSAPP_ACCOUNT_VALIDATION` | `true` |
| `--webhook` / `-w` | `WHATSAPP_WEBHOOK` | — (comma-separated URLs) |
| `--webhook-secret` | `WHATSAPP_WEBHOOK_SECRET` | `secret` |
| `--webhook-events` | `WHATSAPP_WEBHOOK_EVENTS` | — (empty = all) |
| `--webhook-insecure-skip-verify` | `WHATSAPP_WEBHOOK_INSECURE_SKIP_VERIFY` | `false` |
| `--presence-on-connect` | `WHATSAPP_PRESENCE_ON_CONNECT` | `unavailable` |
| `--presence-pulse-enabled` | `WHATSAPP_PRESENCE_PULSE_ENABLED` | `true` |
| `--presence-pulse-interval` | `WHATSAPP_PRESENCE_PULSE_INTERVAL` | `24h` |
| `--presence-pulse-duration` | `WHATSAPP_PRESENCE_PULSE_DURATION` | `5m` |

### Chatwoot (env-only values marked *)

| Flag | Env | Default |
|---|---|---|
| `--chatwoot-enabled` | `CHATWOOT_ENABLED` | `false` |
| — * | `CHATWOOT_URL` | — |
| — * | `CHATWOOT_API_TOKEN` | — |
| — * | `CHATWOOT_ACCOUNT_ID` | — |
| — * | `CHATWOOT_INBOX_ID` | — |
| `--chatwoot-device-id` | — | — (no env mapping; multi-device outbound device) |
| `--chatwoot-import-messages` | `CHATWOOT_IMPORT_MESSAGES` | `false` |
| `--chatwoot-days-limit-import-messages` | `CHATWOOT_DAYS_LIMIT_IMPORT_MESSAGES` | `3` |
| `--chatwoot-import-db-uri` | `CHATWOOT_IMPORT_DB_URI` | — (Postgres direct import) |
| `--chatwoot-import-placeholder-media-message` | `CHATWOOT_IMPORT_PLACEHOLDER_MEDIA_MESSAGE` | `true` |
| `--chatwoot-import-media-with-rest` | `CHATWOOT_IMPORT_MEDIA_WITH_REST` | `false` |
| `--chatwoot-auto-create` | `CHATWOOT_AUTO_CREATE` | `false` |
| `--chatwoot-inbox-name` | `CHATWOOT_INBOX_NAME` | `WhatsApp` |
| `--chatwoot-webhook-url` | `CHATWOOT_WEBHOOK_URL` | — |
| `--chatwoot-webhook-secret` | `CHATWOOT_WEBHOOK_SECRET` | — (empty = unauthenticated inbound webhook) |
| `--chatwoot-reopen-conversation` | `CHATWOOT_REOPEN_CONVERSATION` | `true` |
| `--chatwoot-conversation-pending` | `CHATWOOT_CONVERSATION_PENDING` | `false` |
| `--chatwoot-ignore-jids` | `CHATWOOT_IGNORE_JIDS` | — |
| `--chatwoot-sign-msg` | `CHATWOOT_SIGN_MSG` | `false` |
| `--chatwoot-sign-delimiter` | `CHATWOOT_SIGN_DELIMITER` | `\n\n` |
| `--chatwoot-forward-edits` | `CHATWOOT_FORWARD_EDITS` | `true` |
| `--chatwoot-forward-deletes` | `CHATWOOT_FORWARD_DELETES` | `true` |
| `--chatwoot-message-read` | `CHATWOOT_MESSAGE_READ` | `false` |
| `--chatwoot-message-delete` | `CHATWOOT_MESSAGE_DELETE` | `false` |

### MCP subcommand (local flags)

| Flag | Default |
|---|---|
| `--port` | `8080` |
| `--host` | `localhost` |

## CI/CD

Three workflows under `.github/workflows/`. **There is no PR/push CI for `go test`/`go vet`/lint** — only
image/release pipelines (quality gating is manual).

### `build-docker-image.yaml` — multi-arch image

- **Trigger:** `workflow_dispatch` or push of a `v[0-9]+.[0-9]+.[0-9]+` tag.
- **Jobs:** `build-and-push-amd` (linux/amd64); `build-and-push-arm` (matrix: `arm`→linux/arm64 native,
  `armv7`→linux/arm/v7 via QEMU). Each pushes arch-suffixed tags (`<version>-amd`, `-arm`, `-armv7`) to Docker Hub
  + GHCR.
- **`merge-manifest`:** `docker buildx imagetools create` stitches the three arch tags into a unified `<version>`
  manifest on both registries; **on tag pushes** also creates/promotes `:latest`.

### `release.yml` — GoReleaser binaries

- **Trigger:** `workflow_dispatch` or `v*.*.*` tag; both jobs tag-guarded.
- **`build-linux-windows`:** cross-compilers for arm64/armv7/386/mingw; writes GoReleaser v2 config to `/tmp`
  (not committed); builds linux/amd64, linux/arm64, linux/armv7, linux/386, windows/amd64, windows/386 — all
  `CGO_ENABLED=1` with matching `CC`. Archives + `checksums.txt` → GitHub Releases.
- **`build-macos`:** darwin/amd64 + darwin/arm64 (CGO), separate checksums.
- Both run `goreleaser release --config /tmp/.goreleaser-*.yml --clean --timeout 60m --skip=validate`.

### `set-latest-tag.yaml` — manual latest promotion

- **Trigger:** `workflow_dispatch` with required `tag` input (e.g. `v8.8.0`).
- Validates the tag exists on both registries (`imagetools inspect`), then re-tags it as `:latest` on both.
- Decouples "which release is latest" from "which tag was pushed most recently."

> `AppVersion` is hard-coded `v8.8.0` in `config/settings.go`; release workflows do **not** inject it via ldflags.

## Operational notes

- **Persistence:** always volume-mount `/app/storages` (WhatsApp session + chat DBs) and `/app/statics` (media).
  Losing `whatsapp.db` forces a fresh QR login. For multi-device/long sessions, set `DB_KEYS_URI` so privacy tokens
  survive restarts.
- **Graceful shutdown:** `restServer` traps SIGINT/SIGTERM (15s grace) and closes the Chatwoot Postgres pool + chat DB.
- **Health probe:** `GET /health` (root) → `200` if `DeviceManager.IsHealthy()`, else `503`.
- **REST vs MCP:** one mode per process/container. whatsmeow can't share session state across both in one process.
- **Webhook TLS:** if your webhook endpoint has a self-signed cert / Cloudflare tunnel, set
  `WHATSAPP_WEBHOOK_INSECURE_SKIP_VERIFY=true` (dev/tunnels only — use real TLS in production).
- **Logging:** `json-file` capped (`max-size: 200k`, `max-file: 10`) in this repo's compose.
