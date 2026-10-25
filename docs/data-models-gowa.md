# Data Models — GoWA (gowa backend)

> Generated: 2026-06-17 · Scan: exhaustive · Source of truth: `src/infrastructure/chatstorage/sqlite_repository.go` (schema + migrations) and `src/domains/**`.

GoWA persists data across **two SQLite databases** (plus an optional keys DB and an optional Chatwoot Postgres).
This document covers the **GoWA-owned schema** (the `chatstorage` DB), the migration system, and a summary of the
**domain DTOs** (request/response types). whatsmeow's own `whatsapp.db` schema is managed by the whatsmeow library
and is not documented here.

---

## Databases at a glance

| DB | Config | Owner | Purpose |
|---|---|---|---|
| **chatstorage.db** | `ChatStorageURI` (compile-time default `file:storages/chatstorage.db`) | GoWA | The read-model: chats, messages, reactions, edits, devices, Chatwoot links, forward queue |
| **whatsapp.db** | `DB_URI` (default `file:storages/whatsapp.db`) | whatsmeow | Sessions, identity keys, message state — managed by whatsmeow `sqlstore` |
| **whatsapp-keys.db** (opt) | `DB_KEYS_URI` | whatsmeow | Session/identity/pre-key acceleration so privacy tokens survive restarts |
| **Chatwoot Postgres** (opt) | `CHATWOOT_IMPORT_DB_URI` | Chatwoot (Rails) | Direct history import target — GoWA writes into Chatwoot's schema |

All GoWA tables are **device-scoped**: composite primary keys include `device_id`. The device identity stored is
`client.Store.ID.ToNonAD().String()` (the WhatsApp JID), **not** the internal `instance.ID()` UUID alias.

WAL mode + foreign keys are enabled at the connection URI via `pkg/sqlite.FormatChatStorageURI`.

---

## GoWA schema — `chatstorage.db`

Seven tables, created by the ordered migrations in `sqlite_repository.go::getMigrations()`.

### `chats`

| Column | Type | Notes |
|---|---|---|
| `jid` | VARCHAR(255) NOT NULL | PK part |
| `device_id` | VARCHAR(255) NOT NULL DEFAULT '' | PK part |
| `name` | VARCHAR(255) NOT NULL | Display name |
| `last_message_time` | TIMESTAMP NOT NULL | |
| `ephemeral_expiration` | INTEGER DEFAULT 0 | Disappearing-message timer (seconds) |
| `created_at` | TIMESTAMP DEFAULT CURRENT_TIMESTAMP | |
| `updated_at` | TIMESTAMP DEFAULT CURRENT_TIMESTAMP | |
| `archived` | BOOLEAN DEFAULT FALSE | Migration 13 |

**PK:** `(jid, device_id)`. **Indexes:** `idx_chats_last_message`, `idx_chats_name`, `idx_chats_device`, `idx_chats_archived`.

### `messages`

| Column | Type | Notes |
|---|---|---|
| `id` | VARCHAR(255) NOT NULL | PK part (WhatsApp message ID) |
| `chat_jid` | VARCHAR(255) NOT NULL | PK part |
| `device_id` | VARCHAR(255) NOT NULL DEFAULT '' | PK part |
| `sender` | VARCHAR(255) NOT NULL | Sender JID |
| `content` | TEXT | Message text |
| `timestamp` | TIMESTAMP NOT NULL | |
| `is_from_me` | BOOLEAN DEFAULT FALSE | Outgoing flag |
| `media_type` | VARCHAR(50) | `image`/`video`/`audio`/`ptt`/`document`/`sticker`/`call` |
| `filename` | VARCHAR(255) | |
| `url` | TEXT | Media URL |
| `media_key` | BLOB | Download key |
| `file_sha256` | BLOB | |
| `file_enc_sha256` | BLOB | |
| `file_length` | INTEGER DEFAULT 0 | |
| `call_metadata` | TEXT DEFAULT '' | Migration 15 — JSON for synthetic `media_type='call'` rows |
| `referral_metadata` | TEXT DEFAULT '' | Migration 16 — JSON for Meta Ads CTWA referral |
| `created_at` | TIMESTAMP DEFAULT CURRENT_TIMESTAMP | |
| `updated_at` | TIMESTAMP DEFAULT CURRENT_TIMESTAMP | |

**PK:** `(id, chat_jid, device_id)`. **Indexes:** `idx_messages_{chat_jid,device,timestamp,media_type,sender}`.

### `devices` — registered device registry (persists across restarts)

| Column | Type | Notes |
|---|---|---|
| `device_id` | VARCHAR(255) PRIMARY KEY | Operator-facing device id (from `POST /devices`) |
| `display_name` | VARCHAR(255) DEFAULT '' | |
| `jid` | VARCHAR(255) DEFAULT '' | WhatsApp JID once logged in |
| `created_at` | TIMESTAMP DEFAULT CURRENT_TIMESTAMP | |
| `updated_at` | TIMESTAMP DEFAULT CURRENT_TIMESTAMP |

**Index:** `idx_devices_created_at`.

### `message_reactions`

| Column | Type | Notes |
|---|---|---|
| `message_id` | VARCHAR(255) NOT NULL | PK part |
| `chat_jid` | VARCHAR(255) NOT NULL | |
| `device_id` | VARCHAR(255) NOT NULL DEFAULT '' | PK part |
| `reactor_jid` | VARCHAR(255) NOT NULL | PK part |
| `emoji` | TEXT NOT NULL DEFAULT '' | |
| `is_from_me` | BOOLEAN DEFAULT FALSE | |
| `reaction_timestamp` | TIMESTAMP NOT NULL | |
| `created_at` | TIMESTAMP DEFAULT CURRENT_TIMESTAMP | |
| `updated_at` | TIMESTAMP DEFAULT CURRENT_TIMESTAMP | |

**PK:** `(message_id, reactor_jid, device_id)`. **Index:** `idx_message_reactions_lookup` on `(device_id, chat_jid, message_id)`.

### `message_edits` — append-only edit history

| Column | Type | Notes |
|---|---|---|
| `original_message_id` | VARCHAR(255) NOT NULL | PK part |
| `edit_event_id` | VARCHAR(255) NOT NULL | PK part |
| `chat_jid` | VARCHAR(255) NOT NULL | |
| `device_id` | VARCHAR(255) NOT NULL DEFAULT '' | PK part |
| `editor` | VARCHAR(255) DEFAULT '' | |
| `previous_content` | TEXT DEFAULT '' | |
| `new_content` | TEXT DEFAULT '' | |
| `edited_at` | TIMESTAMP NOT NULL | |
| `created_at` | TIMESTAMP DEFAULT CURRENT_TIMESTAMP | |

**PK:** `(original_message_id, edit_event_id, device_id)`. **FK:** `(original_message_id, chat_jid, device_id)` →
`messages(id, chat_jid, device_id)` `ON DELETE CASCADE`. **Indexes:** `idx_message_edits_{original,device,edited_at}`.

### `chatwoot_message_links` — stable WhatsApp↔Chatwoot mapping

| Column | Type | Notes |
|---|---|---|
| `device_id` | VARCHAR(255) NOT NULL DEFAULT '' | PK part |
| `wa_message_id` | VARCHAR(255) NOT NULL | PK part |
| `wa_chat_jid` | VARCHAR(255) NOT NULL DEFAULT '' | |
| `chatwoot_message_id` | INTEGER NOT NULL DEFAULT 0 | |
| `chatwoot_conversation_id` | INTEGER NOT NULL DEFAULT 0 | |
| `chatwoot_inbox_id` | INTEGER NOT NULL DEFAULT 0 | |
| `chatwoot_contact_inbox_source_id` | VARCHAR(255) NOT NULL DEFAULT '' | |
| `source_id` | VARCHAR(255) NOT NULL DEFAULT '' | `WAID:<id>` |
| `direction` | VARCHAR(20) NOT NULL DEFAULT '' | `incoming`/`outgoing` |
| `is_read` | BOOLEAN DEFAULT FALSE | |
| `created_at` | TIMESTAMP DEFAULT CURRENT_TIMESTAMP | |
| `updated_at` | TIMESTAMP DEFAULT CURRENT_TIMESTAMP | |

**PK:** `(device_id, wa_message_id)`. **Indexes:** `idx_chatwoot_links_chatwoot_id (device_id, chatwoot_message_id)`,
`idx_chatwoot_links_source_id (device_id, source_id)`, `idx_chatwoot_links_conversation (chatwoot_conversation_id, updated_at)`,
`idx_chatwoot_links_unread` covering `(device_id, wa_chat_jid, direction, is_read, updated_at, created_at)`.

### `chatwoot_forward_queue` — durable retry queue for live Chatwoot forwarding

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK AUTOINCREMENT | |
| `device_id` | VARCHAR(255) NOT NULL DEFAULT '' | |
| `event_name` | VARCHAR(80) NOT NULL DEFAULT '' | |
| `wa_message_id` | VARCHAR(255) NOT NULL DEFAULT '' | |
| `payload_json` | TEXT NOT NULL DEFAULT '' | |
| `attempts` | INTEGER NOT NULL DEFAULT 0 | |
| `last_error` | TEXT NOT NULL DEFAULT '' | |
| `next_attempt_at` | TIMESTAMP NOT NULL | |
| `created_at` | TIMESTAMP DEFAULT CURRENT_TIMESTAMP | |
| `updated_at` | TIMESTAMP DEFAULT CURRENT_TIMESTAMP | |

**UNIQUE:** `(device_id, event_name, wa_message_id)`. **Index:** `idx_chatwoot_forward_queue_due (next_attempt_at, id)`.

### `schema_info` — migration version tracker

| Column | Type |
|---|---|
| `version` | INTEGER PK |
| `updated_at` | TIMESTAMP |

---

## Migration system

`InitializeSchema()` reads `MAX(version)` from `schema_info`, then runs each pending migration in order. Each
migration is a single SQL statement run in its own transaction (DELETE+INSERT version row for cross-DB
compatibility — SQLite/MySQL/Postgres).

**`getMigrations()` returns 29 migrations** (cross-DB compatible). Highlights:

| # | Adds |
|---|---|
| 1–3 | Core tables: `chats`, `messages`, `devices` |
| 4–12 | Indexes: messages (chat_jid, device, timestamp, media_type, sender), chats (last_message, name, device), devices (created_at) |
| 13–14 | `chats.archived` + index |
| 15 | `messages.call_metadata` JSON (synthetic call rows) |
| 16 | `messages.referral_metadata` JSON (Meta Ads CTWA) |
| 17–18 | `message_reactions` table + lookup index |
| 19–22 | `message_edits` (FK CASCADE) + indexes |
| 23–27 | `chatwoot_message_links` + 4 indexes (chatwoot id, source id, conversation, unread covering) |
| 28–29 | `chatwoot_forward_queue` + due index |

> **Rule:** migrations are **append-only**. Never insert a migration mid-list — bumping `getMigrations()` order
> corrupts the version tracking of already-deployed databases.

---

## Repository contract — `IChatStorageRepository`

Implemented by `chatstorage.SQLiteRepository`; defined in `domains/chatstorage/interfaces.go`. Method groups:

- **Chat ops:** `CreateMessage`, `CreateReaction`, `CreateIncomingCallRecord`, `StoreChat`, `GetChat`,
  `GetChatByDevice`, `GetChats`, `DeleteChat`, `DeleteChatByDevice`.
- **Message ops:** `StoreMessage`, `StoreMessageEdit`, `StoreMessagesBatch`, `GetMessageByID`,
  `GetMessageByIDAndDevice`, `GetMessageEdits`, `GetMessages`, `SearchMessages`, `DeleteMessage`,
  `DeleteMessageByDevice`, `StoreSentMessageWithContext`.
- **Chatwoot correlation:** `UpsertChatwootMessageLink`, `GetChatwootMessageLinkByWhatsAppID`,
  `GetChatwootMessageLinkByChatwootID`, `GetLatestChatwootMessageLinkByConversation`,
  `GetLatestUnreadChatwootMessageLinkByChat`, `EnqueueChatwootForwardEvent`, `ListDueChatwootForwardEvents`,
  `MarkChatwootForwardEventFailed`, `MarkChatwootForwardEventDone`.
- **Statistics:** `GetChatMessageCount(ByDevice)`, `GetTotalMessageCount`, `GetTotalChatCount`,
  `GetFilteredChatCount`, `GetChatNameWithPushName(ByDevice)`, `GetStorageStatistics`.
- **Cleanup:** `TruncateAllChats`, `TruncateAllDataWithLogging`, `DeleteDeviceData`.
- **Device registry:** `SaveDeviceRecord`, `ListDeviceRecords`, `GetDeviceRecord`, `DeleteDeviceRecord`.
- **Schema:** `InitializeSchema`.

> **Wrapper pattern:** `whatsapp.deviceChatStorage` decorates the repository to inject the owning `device_id`,
> rewriting single-arg lookups to device-scoped variants (e.g. `GetChat` → `GetChatByDevice`). When adding a
> repository method, update **interfaces.go + sqlite_repository.go + chatstorage_wrapper.go** together.

---

## Domain DTO summary

The `domains/` package defines request/response DTOs and interfaces per business area. Full field-level detail
lives in the source; below is the structural map. Binding tags: `json:` (body), `query:`, `form:`, `uri:`.

### `send/` — outbound messages (largest domain)

Shared `BaseRequest` (embedded by most): `Phone`, `Duration *int`, `IsForwarded`. Each message type adds its own
fields and embeds `BaseRequest` (except `PresenceRequest`). Returns `GenericResponse{ message_id, status }`.

| Request struct | Key fields | Notes |
|---|---|---|
| `MessageRequest` | `message`, `reply_message_id *string`, `mentions []string` | Ghost-mentions; `@everyone` |
| `ImageRequest` | `caption`, `image` / `image_url`, `view_once`, `compress`, `reply_message_id` | one of file/URL |
| `VideoRequest` | `caption`, `video` / `video_url`, `view_once`, `compress`, `gif_playback`, `reply_message_id` | ffmpeg |
| `AudioRequest` | `audio` / `audio_url`, `reply_message_id`, `ptt` | PTT → Opus transcode |
| `FileRequest` | `file` / `file_url`, `caption`, `reply_message_id` | ≤ 50 MB |
| `StickerRequest` | `sticker` / `sticker_url` | auto-WebP |
| `ContactRequest` | `contact_name`, `contact_phone` | VCARD |
| `LinkRequest` | `link`, `caption` | OG scrape |
| `LocationRequest` | `latitude`, `longitude` | |
| `PollRequest` | `question`, `options []string`, `max_answer` | |
| `ChatPresenceRequest` | `phone`, `action` (`start`/`stop`) | typing indicator |
| `PresenceRequest` | `type` (`available`/`unavailable`), `is_forwarded` | **does not embed BaseRequest** |

Interfaces: `ITextSender`, `IMediaSender`, `IInteractionSender`, `IPresenceSender` → composed `ISendUsecase`.

### `chat/` — read-side history + chat mutations

Requests: `ListChatsRequest` (`limit`/`offset`/`search`/`has_media`/`archived *bool`),
`GetChatMessagesRequest` (`chat_jid`/`limit`/`offset`/`start_time`/`end_time`/`media_only`/`is_from_me *bool`/`search`),
`PinChatRequest`, `SetDisappearingTimerRequest` (`timer_seconds` ∈ {0,86400,604800,7776000}), `ArchiveChatRequest`.
Responses embed `ChatInfo` and `MessageInfo` entities (with nested `ReactionInfo`). `PaginationResponse{limit, offset, total}`.

### `message/` — post-send actions

Requests: `RevokeRequest`, `DeleteRequest`, `ReactionRequest` (+`emoji`), `UpdateMessageRequest` (+`message`),
`MarkAsReadRequest`, `StarRequest` (+`is_starred`), `DownloadMediaRequest`. All carry `message_id` + `phone`.
Returns `GenericResponse` (or `DownloadMediaResponse` with `file_path`/`file_url`/`file_size`). Interfaces:
`IMessageActions` + `IMessageManagement` → `IMessageUsecase`.

### `group/` — group management

Requests: `JoinGroupWithLinkRequest`, `LeaveGroupRequest`, `CreateGroupRequest` (`title`/`participants[]`),
`ParticipantRequest` (`group_id`/`participants[]`/`action`), `GetGroupParticipantsRequest`,
`GetGroupRequestParticipantsRequest`, `GroupRequestParticipantsRequest` (`action` approve/reject),
`SetGroup{Photo,Name,Locked,Announce,Topic}Request`, `GetGroupInfoFromLinkRequest`, `GroupInfoRequest`,
`GetGroupInviteLinkRequest` (`reset`). Interfaces: `IGroupManagement` + `IGroupParticipants` + `IGroupSettings` → `IGroupUsecase`.

### `user/` — account/profile/listings

Requests: `InfoRequest`, `CheckRequest`, `BusinessProfileRequest`, `AvatarRequest` (`is_preview`/`is_community`),
`ChangeAvatarRequest`, `ChangePushNameRequest`. Responses: `InfoResponse` (devices, verified name, LID/phone cross-resolution),
`AvatarResponse`, `CheckResponse`, `BusinessProfileResponse`, `MyPrivacySettingResponse`, `MyList{Groups,Newsletter,Contacts}Response`.
Interfaces: `IUserInfo` + `IUserProfile` + `IUserListing` + `IUserPrivacy` → `IUserUsecase`.

### `device/` — device CRUD + state

`DeviceState` enum (`disconnected`/`connecting`/`connected`/`logged_in`). `Device` entity (`id`/`phone_number`/
`display_name`/`state`/`jid`/`created_at`). Interface `IDeviceUsecase`.

### `app/` — session lifecycle

No request structs (primitive args). Responses: `DevicesResponse` (`name`/`device`/`jid`), `LoginResponse`
(`image_path`/`duration`/`code`). Interface `IAppUsecase`.

### `newsletter/` — channels

`UnfollowRequest` (`newsletter_id`). Interface `INewsletterUsecase` (currently single method).

### `chatstorage/` — repository entity types (DB-mapped, `db:` tags)

`Chat`, `Message`, `MessageEdit`, `Reaction`, `ChatwootMessageLink`, `ChatwootForwardEvent`, `MediaInfo`,
`DeviceRecord`, plus internal filters (`ChatFilter`, `MessageFilter`). Errors: `ErrMissingDeviceContext`,
`ErrCallOfferMissingPeerJID`. See the schema section above for column mappings.

---

## Cross-cutting data notes

- **Timestamps:** all time fields serialized as RFC3339 strings in DTOs; `time.Local = time.UTC` process-wide.
- **`is_from_me` heuristic:** for appstate patches (delete/star), `is_from_me` is inferred from MessageID length
  (> 22 ⇒ not-from-me).
- **Idempotency keys:** `WAID:<id>` `source_id` (Chatwoot), `(device_id, wa_message_id)` (chatwoot links),
  `(device_id, event_name, wa_message_id)` (forward queue).
- **Cross-device-safe vs device-scoped lookups:** `GetMessageByID` is globally unique (used for reaction/revoke
  sender resolution); all user-facing reads use the `*ByDevice` variants to isolate data per account.
