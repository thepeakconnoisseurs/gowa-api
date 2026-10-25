# API Contracts — GoWA (gowa backend)

> Generated: 2026-06-17 · Scan: exhaustive · Source of truth: `src/ui/rest/*`, `src/ui/mcp/*`, `src/ui/websocket/*`, `src/cmd/{rest,mcp}.go`.
> Machine-readable companion: [`openapi.yaml`](./openapi.yaml) (~4,538 lines).

This document covers **all three surfaces**: the HTTP **REST API** (~77 routes), the **MCP** tool catalog (29 tools),
and the **WebSocket** event stream.

---

## REST API

### Router setup & middleware chain

The Fiber app is assembled in `restServer` (`src/cmd/rest.go`). All routes are mounted under a configurable base
path (`APP_BASE_PATH`, empty by default). The middleware chain, in registration order:

1. `app.Static("{base}/statics", "./statics")` — user media on disk (downloaded/sent media served as URLs).
2. `app.Use("{base}/components", filesystem.New(embedded views/components))` — embedded Vue components.
3. `app.Use("{base}/assets", filesystem.New(embedded views/assets))` — embedded Vue assets.
4. `middleware.Recovery()` — converts panics → JSON envelope (500 `INTERNAL_SERVER_ERROR`; 504 `GATEWAY_TIMEOUT`
   on `context.DeadlineExceeded`; custom status/code from `pkgError.GenericError`).
5. `middleware.RequestTimeout(45s)` — 45s deadline on every request.
6. `middleware.BasicAuth()` — stashes the `Authorization` header into context under key `BASIC_AUTH` (does **not** validate).
7. `logger.New()` — only when `APP_DEBUG=true`.
8. `cors.New(...)` — `AllowOrigins: "*"`, `AllowHeaders: "Origin, Content-Type, Accept"`.

**Public endpoints (before auth):**
- `GET /health` (at root, ignores base path) → `200 OK` if `DeviceManager.IsHealthy()`, else `503`. For probes.
- `POST {base}/chatwoot/webhook` — only when `CHATWOOT_ENABLED`; **mounted before basic-auth** so Chatwoot can call
  it without app credentials (it authenticates via its own shared secret).

**Basic-auth gate (conditional):** if `APP_BASIC_AUTH` is non-empty, Fiber `basicauth.New(...)` is registered.
Multi-credential: each `user:secret` pair populates one `map[string]string`; malformed pairs are fatal at startup.

**Route groups after auth:**
- `apiGroup = app.Group(base)` (or `app` if no base).
- `InitRestDevice(apiGroup)` — `/devices/*` mounted directly (addressed by `:device_id` path param, **not** device-middleware scoped).
- `headerDeviceGroup = apiGroup.Group("", middleware.DeviceMiddleware(dm))` — **all device-scoped routers** (App, Chat, Send, User, Message, Group, Newsletter, `/ws`) registered here.
- Chatwoot sync routes (`POST /chatwoot/sync`, `GET /chatwoot/sync/status`) — authenticated but not device-scoped (take `device_id` in query/body).
- `GET {base}/` — renders embedded Vue index.

### Device scoping (the multi-tenant axis)

`middleware.DeviceMiddleware` (`src/ui/rest/middleware/device.go`) resolves the target WhatsApp account for every
device-scoped route. Priority:

1. Header **`X-Device-Id`** (URL-decoded).
2. Query **`?device_id=`**.
3. The default/only device (single-device deployments can omit the header entirely).

On success it sets `c.Locals("device_id")`, `c.Locals("device", *whatsapp.DeviceInstance)`, and injects the device
into the user context via `whatsapp.ContextWithDevice(...)`. Failure codes: `404 DEVICE_NOT_FOUND` (id supplied but
unresolved), `400 DEVICE_ID_REQUIRED` (no id, no default), `503 DEVICE_MANAGER_UNAVAILABLE` (manager nil).

### Response envelope & status codes

Standard envelope (`utils.ResponseData`):

```json
{ "code": "SUCCESS", "message": "human-readable", "results": <any|omitted> }
```

`Status` is a `json:"-"` field that drives the HTTP status line. Status codes used:

| HTTP | `code` | Meaning |
|---|---|---|
| 200 | `SUCCESS` | OK |
| 400 | `BAD_REQUEST` / `INVALID_REQUEST` | malformed JSON / validation |
| 401 | _(bare)_ | bad Chatwoot webhook secret |
| 404 | `DEVICE_NOT_FOUND` | device middleware could not resolve device |
| 409 | `SYNC_ALREADY_RUNNING` | Chatwoot sync already in progress for device |
| 500 | `INTERNAL_SERVER_ERROR` | recovered panic |
| 503 | `DEVICE_MANAGER_UNAVAILABLE` | manager nil; `/health` failure |
| 504 | `GATEWAY_TIMEOUT` | recovered `context.DeadlineExceeded` |

Business validation errors surface via `utils.PanicIfNeeded(err)` → recovery middleware maps a `pkgError.GenericError`
panic to its declared status/code. **Non-JSON success:** `GET /group/participants/export` streams CSV
(`Content-Disposition: attachment; filename="group-<jid>-participants.csv"`, columns
`participant_jid,phone_number,lid,display_name,role`).

### Complete endpoint table

Paths are relative to `APP_BASE_PATH`. **Auth** = requires basic auth when configured. **DS** = device-scoped
(requires `X-Device-Id` / `?device_id=` unless a default device exists).

#### App / Login (DS) — `ui/rest/app.go`

| Method | Path | Handler | Summary |
|---|---|---|---|
| GET | `/app/login` | `App.Login` | Begin QR login; returns `qr_link` + `qr_duration` |
| GET | `/app/login-with-code` | `App.LoginWithCode` | Request phone pair code; query `phone` |
| GET | `/app/logout` | `App.Logout` | Log current device out |
| GET | `/app/reconnect` | `App.Reconnect` | Reconnect current device |
| GET | `/app/devices` | `App.Devices` | Fetch all known devices |
| GET | `/app/status` | `App.ConnectionStatus` | Connection/login state + JID |

#### User (DS) — `ui/rest/user.go`

| Method | Path | Handler | Summary |
|---|---|---|---|
| GET | `/user/info` | `User.UserInfo` | User info (query) |
| GET | `/user/avatar` | `User.UserAvatar` | User avatar |
| POST | `/user/avatar` | `User.UserChangeAvatar` | Change avatar (multipart `avatar`) |
| POST | `/user/pushname` | `User.UserChangePushName` | Change push name |
| GET | `/user/my/privacy` | `User.UserMyPrivacySetting` | Privacy settings |
| GET | `/user/my/groups` | `User.UserMyListGroups` | List groups (max 500, WA protocol limit) |
| GET | `/user/my/newsletters` | `User.UserMyListNewsletter` | Subscribed newsletters |
| GET | `/user/my/contacts` | `User.UserMyListContacts` | Contacts |
| GET | `/user/check` | `User.UserCheck` | Is number on WhatsApp |
| GET | `/user/business-profile` | `User.UserBusinessProfile` | Business profile |

#### Send (DS) — `ui/rest/send.go`

| Method | Path | Handler | Summary |
|---|---|---|---|
| POST | `/send/message` | `Send.SendText` | Text message |
| POST | `/send/image` | `Send.SendImage` | Image (multipart `image`, compress) |
| POST | `/send/file` | `Send.SendFile` | File (multipart `file`, required) |
| POST | `/send/video` | `Send.SendVideo` | Video (multipart `video`) |
| POST | `/send/sticker` | `Send.SendSticker` | Sticker (multipart `sticker`, auto-WebP) |
| POST | `/send/contact` | `Send.SendContact` | Contact card |
| POST | `/send/link` | `Send.SendLink` | Link preview |
| POST | `/send/location` | `Send.SendLocation` | Location |
| POST | `/send/audio` | `Send.SendAudio` | Audio (multipart `audio`; PTT voice note) |
| POST | `/send/poll` | `Send.SendPoll` | Poll / vote |
| POST | `/send/presence` | `Send.SendPresence` | Broadcast presence (`available`/`unavailable`) |
| POST | `/send/chat-presence` | `Send.SendChatPresence` | Per-chat typing indicator (`start`/`stop`) |

#### Message (DS) — `ui/rest/message.go`

| Method | Path | Handler | Summary |
|---|---|---|---|
| POST | `/message/:message_id/reaction` | `Message.ReactMessage` | React (emoji) |
| POST | `/message/:message_id/revoke` | `Message.RevokeMessage` | Revoke (unsend) |
| POST | `/message/:message_id/delete` | `Message.DeleteMessage` | Delete for me |
| POST | `/message/:message_id/update` | `Message.UpdateMessage` | Edit |
| POST | `/message/:message_id/read` | `Message.MarkAsRead` | Mark read |
| POST | `/message/:message_id/star` | `Message.StarMessage` | Star |
| POST | `/message/:message_id/unstar` | `Message.UnstarMessage` | Unstar |
| GET | `/message/:message_id/download` | `Message.DownloadMedia` | Download media; query `phone` |

#### Group (DS) — `ui/rest/group.go`

| Method | Path | Handler | Summary |
|---|---|---|---|
| POST | `/group` | `Group.CreateGroup` | Create group |
| POST | `/group/join-with-link` | `Group.JoinGroupWithLink` | Join via invite link |
| GET | `/group/info-from-link` | `Group.GetGroupInfoFromLink` | Group info from link |
| GET | `/group/info` | `Group.GroupInfo` | Group info (query) |
| POST | `/group/leave` | `Group.LeaveGroup` | Leave group |
| GET | `/group/participants` | `Group.ListParticipants` | List participants |
| GET | `/group/participants/export` | `Group.ExportParticipants` | Export CSV (no envelope) |
| POST | `/group/participants` | `Group.AddParticipants` | Add participants |
| POST | `/group/participants/remove` | `Group.DeleteParticipants` | Remove participants |
| POST | `/group/participants/promote` | `Group.PromoteParticipants` | Promote to admin |
| POST | `/group/participants/demote` | `Group.DemoteParticipants` | Demote admin |
| GET | `/group/participant-requests` | `Group.ListParticipantRequests` | Pending join requests |
| POST | `/group/participant-requests/approve` | `Group.ApproveParticipantRequests` | Approve requests |
| POST | `/group/participant-requests/reject` | `Group.RejectParticipantRequests` | Reject requests |
| POST | `/group/photo` | `Group.SetGroupPhoto` | Set/remove photo (multipart `photo`) |
| POST | `/group/name` | `Group.SetGroupName` | Rename (1–25 chars) |
| POST | `/group/locked` | `Group.SetGroupLocked` | Toggle locked |
| POST | `/group/announce` | `Group.SetGroupAnnounce` | Toggle announce (admin-only) |
| POST | `/group/topic` | `Group.SetGroupTopic` | Set/remove topic |
| GET | `/group/invite-link` | `Group.GetGroupInviteLink` | Get invite link |

#### Newsletter (DS) — `ui/rest/newsletter.go`

| Method | Path | Handler | Summary |
|---|---|---|---|
| POST | `/newsletter/unfollow` | `Newsletter.Unfollow` | Unfollow newsletter |

#### Chat (DS) — `ui/rest/chat.go`

| Method | Path | Handler | Summary |
|---|---|---|---|
| GET | `/chats` | `Chat.ListChats` | List chats (paginated; `limit`/`offset`/`search`/`has_media`/`archived`) |
| GET | `/chat/:chat_jid/messages` | `Chat.GetChatMessages` | List messages (`limit`/`offset`/`start_time`/`end_time`/`media_only`/`is_from_me`/`search`) |
| POST | `/chat/:chat_jid/pin` | `Chat.PinChat` | Pin/unpin |
| POST | `/chat/:chat_jid/disappearing` | `Chat.SetDisappearingTimer` | Disappearing timer (`0`/`86400`/`604800`/`7776000`) |
| POST | `/chat/:chat_jid/archive` | `Chat.ArchiveChat` | Archive/unarchive |

#### Device management (NOT device-scoped; path-param addressed) — `ui/rest/device.go`

| Method | Path | Handler | Summary |
|---|---|---|---|
| GET | `/devices` | `Device.ListDevices` | List all devices |
| POST | `/devices` | `Device.AddDevice` | Register device (`{"device_id":...}`) |
| GET | `/devices/:device_id` | `Device.GetDevice` | Get one device |
| DELETE | `/devices/:device_id` | `Device.RemoveDevice` | Remove device |
| GET | `/devices/:device_id/login` | `Device.LoginDevice` | QR login |
| POST | `/devices/:device_id/login/code` | `Device.LoginDeviceWithCode` | Pair-code login; query `phone` |
| POST | `/devices/:device_id/logout` | `Device.LogoutDevice` | Logout device |
| POST | `/devices/:device_id/reconnect` | `Device.ReconnectDevice` | Reconnect device |
| GET | `/devices/:device_id/status` | `Device.Status` | Connection status |

#### Chatwoot (mixed scoping) — `ui/rest/chatwoot.go`

| Method | Path | Handler | Auth | Summary |
|---|---|---|---|---|
| POST | `/chatwoot/webhook` | `ChatwootHandler.HandleWebhook` | **no** (secret-auth) | Inbound Chatwoot webhook → send to WhatsApp |
| POST | `/chatwoot/sync` | `ChatwootHandler.SyncHistory` | yes | Start async history sync (`device_id`/`days_limit`/`include_media`/`include_groups`) |
| GET | `/chatwoot/sync/status` | `ChatwootHandler.SyncStatus` | yes | Poll sync progress (`?device_id=`) |

#### WebSocket (DS group) — `ui/websocket/websocket.go`

| Method | Path | Handler | Summary |
|---|---|---|---|
| GET (upgrade) | `/ws` | `websocket.New(...)` | Live events; non-upgrade → `426 Upgrade Required` |

#### Root

| Method | Path | Summary |
|---|---|---|
| GET | `/health` | Liveness/readiness (no base path) |
| GET | `{base}/` | Embedded Vue index page |

**Totals:** 6 App + 10 User + 12 Send + 8 Message + 20 Group + 1 Newsletter + 5 Chat + 9 Device + 3 Chatwoot + 1 WS + 2 root = **77 route registrations**.

### Chatwoot webhook (inbound) detail

`POST /chatwoot/webhook` → `HandleWebhook`. Registered only when `CHATWOOT_ENABLED`, before basic-auth.

**Auth** (`chatwootWebhookAuthorized`): if `CHATWOOT_WEBHOOK_SECRET` is empty → unauthenticated. Otherwise one of:
header `X-Chatwoot-Webhook-Secret`, header `X-Gowa-Chatwoot-Secret`, query `?secret=`, or header
`X-Hub-Signature-256: sha256=<HMAC of body keyed by secret>`. All comparisons use `subtle.ConstantTimeCompare`.

**Behavior:** acts only on `message_created` (outgoing, non-private) and `message_updated`+deleted (when
`CHATWOOT_MESSAGE_DELETE`). Echo-suppression skips messages created by this app and `source_id` starting `WAID:`.
Routing resolves destination via stored `ChatwootMessageLink` → contact's `gowa_device_id`/`gowa_whatsapp_jid` →
`CHATWOOT_DEVICE_ID`. Translates GFM→WhatsApp markdown, optional agent signature, sends attachments-then-text via
`SendUsecase.SendText`, records a `ChatwootMessageLink`, optionally marks inbound read. Always returns `200` (so
Chatwoot never retries). Bad secret → `401`.

---

## MCP (Model Context Protocol) server

Run via `gowa mcp`. Uses `mark3labs/mcp-go` over **SSE** with keep-alive.

- **SSE endpoint:** `http://<host>:<port>/sse` · **Message endpoint:** `http://<host>:<port>/message`
- Defaults: `--host localhost`, `--port 8080` (local to the `mcp` subcommand; independent of root `--port/--host`).
- **No device header** — every tool resolves the default/only device via `helpers.ContextWithDefaultDevice`.
- Client config (e.g. Cursor): `{ "mcpServers": { "whatsapp": { "url": "http://localhost:8080/sse" } } }`

### MCP tool catalog (29 tools)

"Req" = `mcp.Required()` set. Grouped by category.

#### Connection (5)

| Tool | Parameters (name: type, req?) | Summary |
|---|---|---|
| `whatsapp_connection_status` | — | Connected/logged-in/device_id (read-only) |
| `whatsapp_login_qr` | — | QR login; returns base64 PNG + path + code |
| `whatsapp_login_with_code` | `phone: string, req` | Pairing code for multi-device login |
| `whatsapp_logout` | — | Sign out default device |
| `whatsapp_reconnect` | — | Reconnect via stored session |

#### Messaging / Send (6)

| Tool | Parameters | Summary |
|---|---|---|
| `whatsapp_send_text` | `phone` req, `message` req, `is_forwarded`, `reply_message_id`, `mentions[]` | Text; ghost-mentions; `@everyone` |
| `whatsapp_send_contact` | `phone` req, `contact_name` req, `contact_phone` req, `is_forwarded` | Contact card |
| `whatsapp_send_link` | `phone` req, `link` req, `caption` req (handler defaults `""`), `is_forwarded` | Link + caption |
| `whatsapp_send_location` | `phone` req, `latitude` req, `longitude` req, `is_forwarded` | Coordinates (strings) |
| `whatsapp_send_image` | `phone` req, `image_url`, `caption`, `view_once`, `compress`, `is_forwarded` | Image by URL |
| `whatsapp_send_sticker` | `phone` req, `sticker_url`, `is_forwarded` | Sticker (auto-WebP) |

#### Chat / Query (5)

| Tool | Parameters | Summary |
|---|---|---|
| `whatsapp_list_contacts` | — | All contacts |
| `whatsapp_list_chats` | `limit`(25), `offset`(0), `search`, `has_media`(false) | Recent chats |
| `whatsapp_get_chat_messages` | `chat_jid` req, `limit`(50), `offset`(0), `start_time`, `end_time`, `media_only`(false), `is_from_me`, `search` | Messages in a chat |
| `whatsapp_download_message_media` | `message_id` req, `phone` req | Download media → file path |
| `whatsapp_archive_chat` | `chat_jid` req, `archived` req | Archive/unarchive |

#### Group (13)

| Tool | Parameters | Summary |
|---|---|---|
| `whatsapp_group_create` | `title` req, `participants[]` | Create group |
| `whatsapp_group_join_via_link` | `invite_link` req | Join via link |
| `whatsapp_group_leave` | `group_id` req | Leave |
| `whatsapp_group_participants` | `group_id` req | List participants |
| `whatsapp_group_manage_participants` | `group_id` req, `participants[]` req, `action` req (`add`/`remove`/`promote`/`demote`) | Manage members |
| `whatsapp_group_invite_link` | `group_id` req, `reset`(false) | Get/reset invite link |
| `whatsapp_group_info` | `group_id` req | Group info |
| `whatsapp_group_set_name` | `group_id` req, `name` req | Rename |
| `whatsapp_group_set_topic` | `group_id` req, `topic` req | Set topic |
| `whatsapp_group_set_locked` | `group_id` req, `locked` req | Toggle locked |
| `whatsapp_group_set_announce` | `group_id` req, `announce` req | Toggle announce |
| `whatsapp_group_join_requests` | `group_id` req | List pending requests |
| `whatsapp_group_manage_join_requests` | `group_id` req, `participants[]` req, `action` req (`approve`/`reject`) | Approve/reject |

**MCP vs REST:** MCP is a curated subset (App/Connection, Send, Chat/Query, Group). It omits device-management
endpoints, message delete/read/typing, user-login flows, and webhook config. Tool results use
`mcp.NewToolResultStructured` (JSON + human fallback) or `NewToolResultImage` (QR PNG). Tools carry protocol
annotations (`ReadOnlyHint`, `DestructiveHint`, `IdempotentHint`, `Title`).

---

## WebSocket interface

`GET /ws` (upgraded) — a generic broadcast bus. A `Use("/ws")` guard returns `426 Upgrade Required` on non-upgrade.

- **Hub pattern:** package channels `Register`/`Unregister`/`Broadcast`; `RunHub()` is the single goroutine fanning
  out to `Clients map[*websocket.Conn]client`.
- **Inbound from clients:** only `TextMessage` parsed as `{code, message, result}`; `code:"FETCH_DEVICES"` replies
  with `{code:"LIST_DEVICES", result:[devices]}`; other codes ignored.
- **Outbound to clients:** any component pushes a `BroadcastMessage` onto `Broadcast`; **every connected client
  receives every broadcast** (no per-device routing inside the socket).
- **Message format:** `{ "code": "<event>", "message": "<status>", "result": <any> }` as a `TextMessage` frame.
- Event producers (whatsmeow event handlers) translate WA events into `BroadcastMessage` values; e.g. login
  success broadcasts `{code:"LOGIN_SUCCESS"}`, remote logout `{code:"LOGOUT_COMPLETE"}`, device removal
  `{code:"DEVICE_REMOVED"}`.

> **Note:** the `/ws` handler does **not** read a `?device_id=` param; device scoping for pushed events, if any,
> happens upstream at the broadcast producer. Treat the socket as a global event tap.

---

## Outbound webhooks (WA → your service)

When `WHATSAPP_WEBHOOK` is set, GoWA POSTs signed JSON to each URL for WhatsApp events. HMAC header
`X-Hub-Signature-256: sha256=<HMAC-SHA256 of body keyed by WHATSAPP_WEBHOOK_SECRET>`. Filter via
`WHATSAPP_WEBHOOK_EVENTS`. Top-level payload: `{ "event": "...", "device_id": "<wa-jid>", "session_id": "<operator device id>", "payload": {...} }`.
Full schemas in [`webhook-payload.md`](./webhook-payload.md). Event types: `message`, `message.reaction`,
`message.revoked`, `message.edited`, `message.ack`, `message.deleted`, `chat_presence`, `group.participants`,
`group.joined`, `newsletter.{joined,left,message,mute}`, `call.offer`, `label.{edit,association}`.
