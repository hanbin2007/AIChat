# AIChat Relay — Next.js Gateway

Enterprise-grade relay server for [AIChat](..) clients. Wire-compatible 1:1
with the macOS `AIChat Relay` app: paths, request shapes, SSE event names, and
Gemini request transforms all match, so existing Watch / iPhone / Mac builds
can switch to this server by changing only `AI_RELAY_BASE_URL`.

- **Stack**: Next.js 15 (App Router) · React 19 · TypeScript · Tailwind CSS ·
  Material Design 3
- **Storage**: atomic JSON snapshots on disk (`RELAY_DATA_DIR`). No external
  database required. Repository layer is abstracted so Postgres/Redis is a
  drop-in for larger deployments.
- **Scope**: holds `GEMINI_API_KEY`, enforces bearer auth, meters credits,
  issues activation keys / pairing tokens, decodes StoreKit JWS, streams SSE
  to clients, and provides a full admin console.

## Quick start

```bash
cp .env.example .env     # fill in GEMINI_API_KEY, RELAY_BEARER_TOKEN, RELAY_SESSION_SECRET
npm install
npm run dev              # http://localhost:8787
```

On first boot visit <http://localhost:8787/setup> to create the admin account.

## Point the Watch app at this relay

In `Config/Secrets.xcconfig`:

```xcconfig
AI_BACKEND_MODE      = relay
AI_RELAY_BASE_URL    = http:/$()/127.0.0.1:8787
AI_RELAY_BEARER_TOKEN = <value of RELAY_BEARER_TOKEN>
GEMINI_MODEL         = gemini-3-flash-preview
```

(The `//` in URLs must be written as `/$()/` because xcconfig treats `//` as
a comment.)

## Endpoints

| Path | Method | Purpose |
|------|--------|---------|
| `/api/health` | GET | Liveness probe |
| `/api/v1/billing/catalog` | GET | Plans + metering policy (public) |
| `/api/v1/account/status` | GET | Account/device snapshot |
| `/api/v1/chat/stream` | POST | SSE chat stream |
| `/api/v1/audio/transcribe` | POST | Audio → text |
| `/api/v1/memory/extract` | POST | Conversation memory JSON |
| `/api/v1/activation/bootstrap` | POST | Trial activation |
| `/api/v1/billing/purchase/prepare` | POST | StoreKit pre-check |
| `/api/v1/billing/purchase/submit` | POST | Submit JWS transaction |
| `/api/v1/billing/restore` | POST | Restore purchases |
| `/api/v1/account/pairing-token` | POST | 10-minute device-pair code |
| `/api/v1/account/join-paired` | POST | Redeem pairing code |
| `/api/v1/offline/exchange` | POST | Offline activation code |

All SSE frames use the same event names as the macOS relay:
`answer_delta`, `thought_delta`, `model_content`, `attachment`, `done`, `error`.

## Admin console

After login, the following pages are available (`⌘1..⌘0` jumps):

- **Dashboard** — launch checklist, KPIs, system status, recent activity
- **Requests** — live tail, history search, conversation reconstruction
- **Playground** — exercise `/v1/chat/stream` from the browser
- **Accounts** — accounts / devices / keys / activation codes / pairing tokens
- **Billing Studio** — visualised pricing policy + plan editor + simulator
- **Observability** — usage analytics, audit log, diagnostics bundle
- **Models** — Gemini catalogue + capability toggles + default parameters
- **Settings** — 8 visual configuration groups
- **Docs** — API reference with copy-paste examples
- **About** — version + diagnostics download

## Docker

```bash
docker compose up -d
```

The compose file mounts a named volume at `/data` so billing state survives
restarts. Health is polled on `/api/health`.

## License

See repository root.
