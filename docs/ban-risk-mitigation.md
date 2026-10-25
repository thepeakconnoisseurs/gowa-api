# Ban-Risk Mitigation Guide — GoWA Custom Fork

> GoWA drives the **unofficial** WhatsApp multi-device protocol via whatsmeow.
> That violates WhatsApp's Terms of Service by design; Meta can ban numbers at
> any time, and bans are typically permanent with no appeal. This guide REDUCES
> risk — it never eliminates it. For workloads that cannot tolerate a ban, use
> the official WhatsApp Business Cloud API.
>
> Registered in the custom-file inventory (docs/upstream-sync.md). Verified
> against code at v9.7.0 (upstream 5e17e8c, 2026-10-25).

## 1. How this fork's mechanics actually work (verified in code)

### Network egress and proxy
- `WHATSAPP_PROXY` (env) / `--whatsapp-proxy` (flag) -> `client.SetProxyAddress()`
  on the whatsmeow **WebSocket dialer** — applied to the primary client
  (`src/infrastructure/whatsapp/init.go`) AND every multi-device client
  (`src/infrastructure/whatsapp/device_manager.go`). Formats:
  `socks5://user:pass@host:1080`, `http://`, `https://`. Credentials are
  redacted in logs (`proxy.go`). Plain `HTTP_PROXY` env does NOT reach the
  WebSocket (upstream issue #581).
- Scope: WebSocket only. Media downloads and OG-scrape honor standard
  `HTTP_PROXY`/`HTTPS_PROXY`. For full egress via one proxy, set both.
- Limitation: ONE global proxy for ALL registered devices (not per-device).
  Many accounts through one exit IP is a correlation signal; serious
  multi-account setups should run separate GoWA instances per account+IP.
- `APP_TRUSTED_PROXIES` is unrelated (Fiber reverse-proxy trust).

### Device identity (APP_OS)
- At LINKING time: `DeviceProps.Os = "<APP_OS> <AppVersion>"` and
  `PlatformType = 1` (CHROME, waCompanionReg enum) — the label shown on the
  phone under Settings -> Linked Devices.
- Changing `APP_OS` after linking does NOT relabel existing devices; it applies
  to the NEXT link. Never re-link just to rename a label (churn is a risk
  factor of its own).
- This deployment sets `APP_OS=Chrome`, matching the CHROME platform type
  (also upstream's own `.env.example` recommendation).

### WhatsApp anti-spam signals surfaced by the code
- **Error 463 "reachout timelock"** -> surfaced as `WA_REACHOUT_TIMELOCK`
  (HTTP 429): WhatsApp throttles sends to numbers with no prior history.
  GoWA does one presence pre-warm retry; CALLERS must treat a 429 as a hard
  backoff (hours), never a retry storm.
- `WHATSAPP_ACCOUNT_VALIDATION=true` avoids sending to unregistered numbers.
- Presence pulse (defaults 24h interval / 5m duration) mimics natural
  availability cycles; keep the defaults.

## 2. Ban-risk factors (ranked by community-observed impact)

1. Recipient reports & blocks — the #1 trigger; no config fixes this.
2. Cold outreach to non-contacts (the 463 path).
3. Volume spikes on freshly linked numbers.
4. Number quality: VoIP/virtual numbers fall fast; aged real SIMs last.
5. Datacenter egress IPs; many accounts per IP; geo mismatch with the number.
6. Content patterns: identical blasts, shortlinks, mass forwards, bulk group adds.
7. Bot behavior: instant 24/7 replies, read-all-instant, fixed intervals
   without jitter.
8. Device churn: frequent logout/relink cycles.
9. Periodic Meta crackdown waves — residual risk that cannot be zeroed.

## 3. Applied configuration snapshot (this deployment, 2026-10-25)

| Key | Value | Note |
|---|---|---|
| `APP_OS` | `Chrome` | applies to new links only |
| `DB_KEYS_URI` | `file:storages/whatsapp-keys.db` | durable keys acceleration; privacy tokens stay in primary storage |
| `WHATSAPP_AUTO_REPLY` | `""` | disabled — reply pacing belongs to callers |
| `WHATSAPP_AUTO_MARK_READ` | `false` | |
| `WHATSAPP_ACCOUNT_VALIDATION` | `true` | |
| `WHATSAPP_PRESENCE_PULSE_ENABLED` | `true` | 24h/5m defaults kept |
| `WHATSAPP_PROXY` | *(empty — RESERVED)* | fill with a sticky residential proxy when available; also set `HTTP_PROXY`/`HTTPS_PROXY` for media |

## 4. Caller-side discipline (n8n / API clients) — the highest-leverage layer

GoWA has NO internal send rate limiter; all pacing is the caller's job:

- **Warm-up ramp**: start around 20 msgs/day, increase over 2-4 weeks; replies
  to inbound are far safer than cold outbound.
- **Humanized pacing**: random jitter between sends (never fixed intervals),
  business hours, conservative daily caps.
- **Content**: personalized, opt-in lists only; no identical bulk text; avoid
  shortlinks and mass forwarding.
- **Backoff**: on `WA_REACHOUT_TIMELOCK` (429) wait hours; halve volume for a day.
- **Network (when proxy is enabled)**: sticky residential IP geo-matched to the
  number's country; one account per exit IP.

## 5. Do NOT

- re-link devices just to change the displayed label
- brute-force 463 / retry-storm the API after 429
- enable instant auto-reply or instant read-all in production
- run several accounts behind one shared datacenter IP
- blast identical content or bulk-add strangers to groups
- experiment on the primary business number — use a spare, aged number first

## 6. Monitoring

- Watch webhooks: logout events (`LOGOUT_COMPLETE`, device removal,
  `StreamReplaced`) are early indicators that a session is in trouble.
- Keep the `storages/` volume persistent — losing `whatsapp.db` forces a fresh
  QR link (churn). `DB_KEYS_URI` now keeps key acceleration durable too.

## 7. Sources (community consensus, not official Meta documentation)

- Kookeey: <https://www.kookeey.net/en/news/ipproxyxw/how-to-use-proxy-ip-cleverly-to-ensure-your-whatsapp-account-is-not-blocked>
- Reddit anti-ban toolkit (Baileys warm-up 20/day ramp, risk scoring):
  <https://www.reddit.com/r/node/comments/1rb1qj/build_an_antiban_toolkit_for_whatsapp>
- Evolution API / WasenderAPI warm-up guides; residential-proxy vendor
  guidance (Evomi, RapidSeedbox).
