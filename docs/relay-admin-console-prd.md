# AIChat Relay Admin Console — Product Requirements Document

**Status:** As-shipped on 2026-05-10 (PR #73 merged to feature branch + deployed to `https://ai.origenclub.cn`).
**Owner:** Relay platform.
**Tech surface:** Next.js 15 App Router, MUI v6 (Material Design 2), TypeScript, React 19, Emotion 11.
**Source of truth:** `relay/src/app/`, `relay/src/components/`, `relay/src/theme/`.

---

## 1. Overview

The Admin Console is the operator-facing web UI for an AIChat Relay instance — a Next.js gateway that holds Gemini API keys, gates AIChat client traffic on bearer tokens / device activation, meters credit consumption, and surfaces audit / observability data. Operators (one to a few admins per deployment) use the console to:

- Watch live request traffic and replay conversations.
- Issue / revoke admin and client tokens.
- Manage end-user accounts, devices, keys, activation codes.
- Tune the credit policy and ship plans.
- Diagnose problems before clients report them.
- Run an interactive playground against the relay's own `/api/v1/chat/stream` to verify upstream behaviour.

The console is not customer-facing — there is no signup / billing flow exposed here. End users reach the relay strictly via the AIChat watchOS / iOS / macOS clients.

### Why this PRD

A prior iteration of the console used a hand-rolled Material Design 3 layer (custom HCT tokens, Tailwind 3, fifteen self-built primitives). That layer had real interaction gaps (no real ripple, no animated tab indicator, raw `<table>` in seven pages, raw `<select>` in two, no Menu / Tooltip / DatePicker, etc.) and could never realistically catch up to the spec inside a hand-rolled system. The console was rewritten end-to-end onto **Material Design 2 via MUI v6** (the only production-ready React Material library in 2026). This PRD captures the post-rewrite contract.

---

## 2. Goals and non-goals

### Goals

1. **Single source of truth for theming.** All visual surfaces resolve through one MUI theme; no parallel CSS systems.
2. **No raw `<table>` / `<select>`.** Tabular surfaces use `DataGrid` (sortable, paginated). Choice inputs use `Select` / `ToggleButtonGroup` / `Autocomplete`.
3. **Real interaction primitives.** Ripple, focus traps, ESC dismissal, sliding tab indicators come from MUI defaults — not hand-rolled.
4. **Zero zh-Hans loss** vs. the prior console; existing operators keep all in-product copy.
5. **Light + dark scheme switching** without flash, persisted across reloads.
6. **One-screen daily ops.** Dashboard surfaces health + recent activity in one viewport on a 1280px monitor.
7. **One-shot rebuild.** Whole console ships in one PR; no M3/M2 coexistence period.

### Non-goals

- A consumer-facing portal. (Account self-service, password reset, signup, etc., are explicitly out of scope.)
- Internationalization framework. zh-Hans copy is hard-coded. There is no i18n routing or runtime locale switch.
- Mobile-first responsive overhaul. Layouts target ≥ 1024px viewport; below that, surfaces still function (MUI defaults + flexible Stack/Grid) but are not visually optimized.
- Visual regression testing rig. Out of scope; covered by manual eyeball + UI smoke tests.
- Stateful multi-snackbar stacks. Snackbar surface is one-at-a-time queued.
- Charts library. Observability bar charts stay as inline SVG; MUI X Charts is deferred.

---

## 3. Users and primary flows

### Primary persona

**Relay operator.** A small-team admin (often the same person who deployed the relay) who has shell access to the EC2 box, holds the `RELAY_ADMIN_PASSWORD`, and wants to keep the relay healthy with minimal friction.

### Critical flows

| # | Flow | Surfaces touched |
|---|---|---|
| 1 | Stand up a fresh relay | `/setup` → `/login` → `/dashboard` |
| 2 | Daily health check | `/dashboard` (status + KPIs) |
| 3 | Diagnose a customer complaint | `/requests` → row click → `DetailDrawer` → `/requests/conversations/[id]` |
| 4 | Issue a Watch beta tester an activation code | `/accounts` (codes tab) → "生成激活码" |
| 5 | Bump trial credits / change pricing | `/billing` → save banner |
| 6 | Rotate a leaked admin token | `/settings` → Auth & Tokens → revoke |
| 7 | Test a new prompt against the live upstream | `/playground` |
| 8 | Watch live SSE traffic during a load test | `/requests` → Live tab |
| 9 | Audit-log review for a security incident | `/observability` → Audit log tab |
| 10 | Onboard a teammate (read-only) | `/about` (dump cuffs + downloads) |

---

## 4. Information architecture

### Sitemap

```
/                         redirect → /setup | /login | /dashboard
/login                    public
/setup                    public, gated to first-run
/(admin)/                 session-gated layout group
  ├─ dashboard            health + KPIs + recent activity
  ├─ requests             live + history + conversation list
  │    └─ conversations/[id]   reconstructed turn-by-turn view
  ├─ playground           interactive /chat/stream tester
  ├─ accounts             billing entities
  │    └─ [id]            account detail
  ├─ billing              pricing studio + plans + transactions
  ├─ observability        usage + audit log + diagnostics
  ├─ models               model catalog (read-mostly)
  ├─ settings             gateway / upstream / tokens / limits / billing / obs / l10n
  ├─ docs                 API docs + Watch xcconfig snippet
  └─ about                deployment + diagnostics
```

### Nav grouping

The left rail collapses to a 80px icon strip and expands to 256px on hover. Items group into three sections:

- **Core:** Dashboard, Requests, Playground.
- **Billing:** Accounts, Billing Studio, Observability.
- **System:** Models, Settings, Docs, About.

A keyboard shortcut accelerator is rendered to the right of the label when the rail is expanded:

```
⌘1 Dashboard    ⌘4 Accounts        ⌘7 Models
⌘2 Requests     ⌘5 Billing Studio  ⌘8 Settings
⌘3 Playground   ⌘6 Observability   ⌘9 Docs
                                   ⌘0 About
```

`⌘K` opens the command palette (`Dialog` + filter list of nav items, free-text search).

---

## 5. Visual design system

### 5.1 Palette

Brand seed: `#4F6AF0`. Tokens are exposed as MUI CSS variables (`--mui-palette-*`) so plain CSS in `globals.css` can reference them.

**Light scheme**

| Role | Hex |
|---|---|
| `primary.main` | `#4F6AF0` |
| `primary.light` | `#7E8EF6` |
| `primary.dark` | `#2E48C7` |
| `secondary.main` | `#5B5F7A` |
| `error.main` | `#BA1A1A` |
| `warning.main` | `#B8860B` |
| `info.main` | `#3B6EE6` |
| `success.main` | `#2E7D32` |
| `background.default` | `#FBF8FF` |
| `background.paper` | `#FFFFFF` |
| `text.primary` | `#1B1B21` |
| `text.secondary` | `#464651` |
| `divider` | `#C6C6D0` |

**Dark scheme**

| Role | Hex |
|---|---|
| `primary.main` | `#BAC3FF` |
| `primary.contrastText` | `#062089` |
| `secondary.main` | `#C4C7E5` |
| `error.main` | `#FFB4AB` |
| `warning.main` | `#FFD080` |
| `info.main` | `#A8C6FF` |
| `success.main` | `#A8D8AB` |
| `background.default` | `#131318` |
| `background.paper` | `#1F1F25` |
| `text.primary` | `#E4E1EA` |
| `divider` | `#464651` |

Source: `relay/src/theme/palette.ts`.

### 5.2 Typography

- Family: Roboto Flex → Noto Sans SC → system. Loaded via Google Fonts `<link>` in `RootLayout`.
- Mono: Roboto Mono (declared in the same `<link>`).
- `htmlFontSize` 16 / `fontSize` 14.
- Headings 500 weight (h1 down to h6); body 400; button 500 + `textTransform: none`.
- Caption is the workhorse for metadata strips throughout the app.

Source: `relay/src/theme/typography.ts`.

### 5.3 Shape and elevation

- Corner radius default `12`. `Button` overrides to `999` (pill). Cards use `16`.
- `Button` defaults to `disableElevation: true`. We do not lean on shadow for hierarchy; we use outlined Cards + section bg + bordered AppBar instead.
- AppBar is `color="default"`, `elevation={0}`, `borderBottom: 1px divider`.

### 5.4 Component defaults

Configured in `relay/src/theme/components.ts`. Key opinions:

| Component | Default |
|---|---|
| `MuiButton` | `variant: "contained"`, `disableElevation`, pill 999, height 40 (32 small) |
| `MuiTextField` | `variant: "outlined"`, `size: "small"`, `fullWidth` |
| `MuiOutlinedInput` | `borderRadius: 12` |
| `MuiCard` | `variant: "outlined"`, `borderRadius: 16` |
| `MuiPaper` | `elevation: 0`, `backgroundImage: none` |
| `MuiAppBar` | `color: "default"`, `elevation: 0`, bordered bottom |
| `MuiTab` | `textTransform: "none"`, `fontWeight: 500`, `minHeight: 48` |
| `MuiChip` | `borderRadius: 8` |
| `MuiDialog.paper` | `borderRadius: 16` |
| `MuiAlert` | `borderRadius: 12` |
| `MuiTableCell.head` | `fontWeight: 600`, `color: text.secondary` |

### 5.5 Color scheme switching

The console uses MUI v6 CSS variables mode (`extendTheme`). The dark/light flip is handled by `useColorScheme()` in the shell. Pre-hydration mode flicker is prevented by `<InitColorSchemeScript attribute="data-mui-color-scheme" modeStorageKey="relay_theme" />` injected first in `<body>`. Storage key `relay_theme` carries forward from the prior implementation.

Source: `relay/src/theme/index.ts`, `relay/src/app/providers.tsx`, `relay/src/app/layout.tsx`.

### 5.6 Iconography

Per-icon imports from `@mui/icons-material`. No icon font, no SVG sprites. Material Symbols web font is **not** loaded.

The shell maps abstract icon names (`"Dashboard"`, `"Cable"`, `"Forum"`, etc.) to MUI icon components via `relay/src/components/shell/nav-icon.tsx`. Pages import icons directly.

---

## 6. Cross-cutting concerns

### 6.1 Authentication

- `/login` posts `{username, password}` to `/api/admin/login`. On 200, the server sets an HTTP-only session cookie (signed with `RELAY_SESSION_SECRET`). The page then calls `router.push("/dashboard")` and `router.refresh()`.
- The `/(admin)` route group's `layout.tsx` is a server component that calls `readSession()` and `redirect("/login")` if absent. Identical gate routes through `/setup` for first-run.
- Logout: `POST /api/admin/logout` (called from the shell footer).

### 6.2 First-run setup

`/setup` is a 5-step `Stepper`:

1. 欢迎 (welcome copy, primary CTA "开始")
2. 管理员账户 (username + password ≥ 8 chars; "下一步" disabled until valid)
3. 上游 Gemini (info-only, points to `GEMINI_API_KEY` env)
4. Bearer Token (info-only, points to `RELAY_BEARER_TOKEN` env; "创建并登录" calls `POST /api/admin/setup`)
5. 完成 (success Alert + xcconfig snippet for the Watch client; CTA goes to `/dashboard`)

A server-side `/setup` page redirects to `/login` once the boot data file says setup is complete (`settingsStore().isSetupComplete()`).

### 6.3 zh-Hans copy

All in-product strings are zh-Hans, hard-coded in JSX. There is no i18n framework. A repo-level invariant — the rewrite preserves all 383 unique zh-Hans strings vs. the M3 baseline — is verified on each PR by:

```sh
rg -uo '[一-鿿]+' src/app src/components | sort -u
```

against the merge base; only new additions (e.g. new loading states or Tooltips) are acceptable.

### 6.4 Accessibility

- All primary interactive elements come from MUI components, which provide ARIA roles and keyboard handling (focus trap on Dialog, ESC to close, tab navigation).
- `Tooltip` is used on icon-only IconButtons in the rail and table action columns.
- `aria-label` is set on every standalone IconButton (e.g. shell footer "切换主题", "注销"; DetailDrawer "返回").
- Buttons use Chinese labels; their accessible name is the visible text.
- `<html lang="zh-Hans">` is set in `RootLayout`.
- Color contrast: the brand blue has `≥ 4.5:1` against `background.paper` in both schemes by construction (light/dark palettes seeded from the same hue but with adjusted lightness).

### 6.5 Loading / empty / error patterns

- **Loading:** simple "加载中…" text in `text.secondary` for full-page placeholders. Inline operations use button label swap (e.g. "登录中…", "处理中…", "签发中…").
- **Empty:** centered Stack with a faded MUI icon (`fontSize: 36, opacity: 0.5`), a one-line headline, and an optional caption explaining how to populate.
- **Error (form):** `Alert severity="error"` rendered above the action area.
- **Error (banner):** `Alert severity="warning"` with `AlertTitle` for unsaved-changes / advisories.
- **Toast (transient success/error):** `useSnackbar().push({message})` — single-stack queue.

### 6.6 Responsive layout

Targets `≥ 1024px`. The shell rail collapses on `< md` (`xs/sm`); the Right SSE pane in `/playground` hides on `< md`. Tables (`DataGrid`) horizontal-scroll inside their card. There is no dedicated mobile menu; the design assumes admin use cases happen on a desktop.

### 6.7 Markdown rendering

`@/components/markdown.tsx` wraps `react-markdown` with:

- `remark-gfm` (tables, task lists, strikethrough)
- `remark-math` + `rehype-katex` (KaTeX math)

Visual styling lives in `globals.css` under `.markdown-body`, referencing `--mui-palette-*` so the rendered Markdown tracks light/dark. Used in three places:

1. `/playground` — assistant message bubble + thought block (collapsed in an `Accordion`).
2. `/requests/conversations/[id]` — every Bubble + ThoughtBlock.
3. `/requests` (DetailDrawer) — the response preview tab.

KaTeX overflow is guarded by a `.markdown-body .katex-display { overflow-x: auto }` rule so long display equations scroll inside the bubble instead of blowing out width.

---

## 7. Page specifications

Each page below documents: URL, purpose, audience, key API calls, layout, components, primary interactions. Source files live under `relay/src/app/`.

### 7.1 `/login`

- **Purpose:** authenticate an admin.
- **Audience:** any operator with credentials.
- **API:** `POST /api/admin/login`.
- **Layout:** centered `Card` (max 440 px) with avatar + title "AIChat Relay" / "管理控制台".
- **Components:** TextField (用户名 + 密码 with leading icons), Alert (error), Button (登录), Link (前往初始化 → `/setup`).
- **Interactions:** Submit on Enter; loading state via button text "登录中…"; on success → push `/dashboard`.
- **Source:** `src/app/login/page.tsx`.

### 7.2 `/setup`

- **Purpose:** first-run admin account creation.
- **Audience:** the person installing the relay.
- **API:** `POST /api/admin/setup`.
- **Layout:** centered `Card` (max 720 px) with `Stepper` (alternativeLabel) for 5 steps.
- **Components:** Stepper, TextField, Alert with AlertTitle, Button.
- **Interactions:** "下一步" disabled until step rules are satisfied (e.g. password ≥ 8 chars on step 1). Final success step shows xcconfig snippet for the Watch client.
- **Source:** `src/app/setup/setup-form.tsx` (page is a server component that gates on `isSetupComplete()`).

### 7.3 `/dashboard`

- **Purpose:** at-a-glance health + last-24h KPIs.
- **Audience:** operator on a daily cadence.
- **APIs:** `configDiagnostics()`, `billingStore().listAll()`, `requestLog().listActivity()`, `metrics().snapshot()` (all server-side, RSC).
- **Layout:**
  - LaunchChecklist (Gemini key / bearer / listener / first traffic).
  - 4-up KpiCard grid: 24h requests (with sparkline), Token in/out, latency p50/p95, error rate.
  - Two-column section: System status (left, lg=8) + Top models 24h (right, lg=4).
  - Recent activity table (last 10 rows).
  - Footer caption: total credit balance.
- **Components:** KpiCard, LaunchChecklist, Card / CardHeader, MUI `Table` (small), Chip (status), MuiLink for "查看全部 →".
- **Source:** `src/app/(admin)/dashboard/page.tsx`.

### 7.4 `/requests`

- **Purpose:** live + historical SSE-aware request log; entry point into the conversation viewer.
- **Audience:** operator triaging a complaint or load test.
- **APIs:**
  - `GET /api/admin/requests` (history)
  - `GET /api/admin/requests/stream` (SSE, "live" view)
  - `GET /api/admin/conversations` (conversations tab)
- **Layout:** ToggleButtonGroup (Live / History / Conversations) + search TextField + level Chip filters; below that a `DataGrid` (history/live) or a divided list (conversations).
- **Components:**
  - `DataGrid` (8 columns): 时间, 端点 (mono), 状态 (Chip color-coded), 延迟, Tokens, 模型, 设备, Credits.
  - `Drawer` (right-anchored, max 520 px) for row detail with Tabs request / response / stream.
  - Detail drawer "response" tab renders Markdown via `<Markdown>`.
- **Interactions:** clicking a row opens the Drawer; ⏸️ Pause / ▶️ Resume IconButton in shell `actions` slot during Live; level Chips toggle inclusion; search filters across path / model / accountID / message.
- **Source:** `src/app/(admin)/requests/page.tsx`.

### 7.5 `/requests/conversations/[id]`

- **Purpose:** reconstructed turn-by-turn conversation view (the Swift relay reconstruction port).
- **Audience:** operator investigating a customer's specific session.
- **API:** `GET /api/admin/conversations/[id]`.
- **Layout:** header `Card` with overview stats; main grid splits left (turns) lg=8 and right (sticky stat panel) lg=4.
  - Each turn is an `<article>` with: user Bubble, ThoughtBlock (Accordion), assistant Bubble, optional error Bubble, then a metadata Stack (time / model / intensity / token in→out / credits / latency / finishReason).
  - Right rail: Model breakdown LinearProgress per model + "Replay in Playground / Export JSON / Flag for review" outlined buttons.
- **Components:** MUI Card, Avatar, Chip, Accordion (ThoughtBlock), LinearProgress, Markdown bubble content, Switch ("Reveal" toggle to surface redacted text).
- **Interactions:** "Reveal" toggle in shell `actions`; back arrow IconButton; stat panel sticky on lg.
- **Source:** `src/app/(admin)/requests/conversations/[id]/page.tsx`.

### 7.6 `/playground`

- **Purpose:** dogfood the relay's own `/api/v1/chat/stream` end-to-end, including thinking deltas + raw SSE.
- **Audience:** operator validating a model / prompt / intensity setting.
- **API:** `POST /api/v1/chat/stream` (own relay).
- **Layout:** two-column on `≥ md`: chat panel (left, flex 1) + Raw SSE pane (right, 360 px). Sticky settings header on top of left panel:
  - Model `Select`, ToggleButtonGroup for thinking intensity (`fast` / `balanced` / `deep` / `extreme`), Chips for Google Search and Code Execution toggles, two TextFields (Authorization bearer; system prompt).
  - Below: scrollable message list. Each assistant message bubble:
    - Optional ThoughtBlock (Accordion with `💭 Thought · N chars`).
    - Markdown body.
    - Optional `finishReason` line if not `STOP`.
  - Footer: textarea + send Button (Enter sends, Shift+Enter newlines).
- **Components:** Select / MenuItem / FormControl / InputLabel, ToggleButtonGroup, Chip, TextField multiline, Accordion, Markdown, IconButton (Visibility toggle for raw events).
- **Interactions:** SSE stream is consumed manually with `ReadableStream.getReader()` + a buffered line-splitter; events `answer_delta` / `thought_delta` / `done` / `error` map to message updates; raw events tail-buffered to last 100.
- **Source:** `src/app/(admin)/playground/page.tsx`.

### 7.7 `/accounts`

- **Purpose:** browse and act on the billing entities.
- **Audience:** operator issuing trial credits, revoking devices, seeding activation codes.
- **API:** `GET /api/admin/billing`, plus `POST/DELETE` action endpoints.
- **Layout:** scrollable Tabs (5 tabs with row counts) + search TextField + tab-specific action button.
  - **账户:** DataGrid columns 名称 (link to `/accounts/[id]` + accountID mono), 状态 (Chip), 来源, 余额, 到期, 最近使用, action IconButtons (发额度 → GrantDialog, 详情 → link).
  - **设备:** DataGrid with platform (icon + label), alias / deviceID, account link, key prefix, last seen, unbind IconButton.
  - **Keys:** DataGrid with masked Key value (`abcd1234••••`), reveal toggle Chip, account link, state Chip, source, issuedAt.
  - **激活码:** DataGrid with code (mono), plan, credits, expiresAt, state Chip, note, revoke IconButton (only for `unused`). "生成激活码" CTA opens an ActivationCodeDialog.
  - **配对:** DataGrid with token, account, device, expiresAt, revoke IconButton.
- **Components:** DataGrid (MIT), Chip, IconButton + Tooltip, Dialog (GrantDialog, ActivationCodeDialog), Snackbar (action confirmations).
- **Interactions:** every destructive action goes through `window.confirm`; success → `snackbar.push({message: "..."})` + refresh list.
- **Source:** `src/app/(admin)/accounts/page.tsx`.

### 7.8 `/accounts/[id]`

- **Purpose:** drill into one account: its devices, keys, grants, recent usage. Also where balance / state / admin notes get edited.
- **API:** `GET /api/admin/accounts/[id]`, `PATCH /api/admin/billing/{account,device,key}`, `PATCH /api/admin/billing/grant/[id]`, `DELETE /api/admin/billing/device`.
- **Layout:**
  - Header Card: avatar + display name + state Chip + source Chip + accountID (mono) + adminNote + "编辑账户" button.
  - 3-up KPI row: 可用额度 (sum of remaining grants), 最近到期, 最近使用.
  - Sectioned Cards: 设备 / Keys / Grants / 最近用量 (last 50 rows reversed), each backed by an MUI `<Table size="small">` (small enough that DataGrid is overkill).
- **Components:** Card, CardHeader, Table, Chip, IconButton (edit / unbind / tune), Dialog (4 dialogs for account / device / key / grant edits), Alert in KeyEditDialog when state=`revoked`.
- **Interactions:** every edit flow is a Dialog with Cancel / Save (loading-state via `Save → 处理中…`).
- **Source:** `src/app/(admin)/accounts/[id]/page.tsx`.

### 7.9 `/billing`

- **Purpose:** edit pricing policy, manage plans, browse transactions.
- **API:** `GET /api/admin/billing`, `POST /api/admin/billing/policy`.
- **Layout:** `Tabs` (Plans / Pricing Policy / Transactions). On the Pricing Policy tab:
  - **Left lg=8:** Credit Calculator card (Sliders for Input / Output tokens / Search count, audio Switch; large total credit pill + USD; LinearProgress bars for input / output / search shares). Below: per-rate Card grid (one per `MeteringRate`).
  - **Right lg=4 (sticky):** Trial Policy card with sliders for credit→USD rate, credit multiplier, trial credits, trial days, low-balance threshold, max bound devices.
- **Dirty state:** if `policy` or `plans` differ from the loaded snapshot, an Alert ribbon appears at the top with "放弃" / "保存".
- **Plans tab:** Card grid editor; each plan card has TextFields for ID / 标题 / Product ID / 价格 / 月度 credits + delete button. Final card is a dashed-border "添加套餐" placeholder.
- **Transactions tab:** Table with Transaction ID (mono) / Product / Env / Purchased / Expires / Revoked Chip.
- **Components:** ToggleButtonGroup (none used; chips replace it for source on plans), Slider, Switch, LinearProgress, Card, TextField, Chip.
- **Source:** `src/app/(admin)/billing/page.tsx`.

### 7.10 `/observability`

- **Purpose:** usage rollups + audit log + diagnostic exports.
- **API:** `GET /api/admin/requests`, `GET /api/admin/audit`.
- **Layout:** `Tabs` (Usage / Audit log / Diagnostics).
  - **Usage:** Range ToggleButtonGroup (1h / 24h / 7d / 30d) + 3-up custom bar charts (Requests / Tokens / Credits). Below: error distribution Card (path → count Chips).
  - **Audit log:** DataGrid with timestamp / action / actor + role Chip / IP / hash prefix.
  - **Diagnostics:** download buttons (requests JSON / audit JSON / Prometheus metrics) opening into new tabs / saving as files.
- **Charts:** custom inline SVG (no MUI X Charts dependency); each bar uses `bgcolor: primary.light` and the column total is shown below.
- **Source:** `src/app/(admin)/observability/page.tsx`.

### 7.11 `/models`

- **Purpose:** read-mostly catalog of upstream models with capability chips.
- **API:** in-memory `DEFAULT_MODELS` from `@/lib/gemini/models`.
- **Layout:** responsive Card grid (1 / 2 / 3 columns at xs / md / xl); each card lists displayName, modelID (mono), family, capability Chips (Thinking / Search / Code / Audio / Vision), supported intensities Chips, and a "在 Billing Studio 中编辑计价 →" link.
- **Source:** `src/app/(admin)/models/page.tsx`.

### 7.12 `/settings`

- **Purpose:** edit relay runtime configuration.
- **API:** `GET /api/admin/settings`, `PATCH /api/admin/settings`, `POST/DELETE /api/admin/tokens`.
- **Layout:** centered max-width 1080 px column with section Cards (`bgcolor: action.hover` to indicate "settings group"):
  1. **Gateway:** allow LAN switch, request body MB slider, CORS origins Autocomplete (multi, freeSolo). Save button per section.
  2. **Upstream · Gemini:** timeout slider (sec → ms), retries slider, retry mode ToggleButtonGroup, health probe interval.
  3. **Auth & Tokens:** "签发新 token" button → TokenIssueDialog (label + scope Chips + RPM slider; on success, surface the token value in a one-shot Alert with a copy block). Token table below.
  4. **Rate limits:** four sliders (global RPM / per-token RPM / max concurrent streams / per-IP RPM).
  5. **Billing mode:** three switches (trial / subscription / offline) + Alert showing current StoreKit verify mode.
  6. **Observability:** activity log size, debug log size, debug-logging switch, log sampling rate, Prometheus enable.
  7. **Localization:** default locale ToggleButtonGroup (zh-Hans / English) + timezone TextField.
- **Persistence:** every "保存 X" button calls `PATCH /api/admin/settings` with the relevant slice; success → `snackbar.push({message: "已保存"})`.
- **Components:** Card sections, Switch / FormControlLabel, custom `SliderField` (label + value pill + Slider), ToggleButtonGroup, Autocomplete (CORS), Dialog (TokenIssueDialog), Alert (info banner up top + dialog warnings).
- **Source:** `src/app/(admin)/settings/page.tsx`.

### 7.13 `/docs`

- **Purpose:** API reference + Watch xcconfig snippet.
- **Layout:** sticky aside (links to anchor IDs) + main column with one Card per endpoint (8 endpoints: health, catalog, status, chat, transcribe, memory, bootstrap, offline). A featured-on-top Card with `bgcolor: action.hover` shows the xcconfig snippet for the Watch client. Tabs above the endpoint cards toggle language hint (curl / Swift / Node) — currently informational only.
- **Source:** `src/app/(admin)/docs/page.tsx`.

### 7.14 `/about`

- **Purpose:** dump deployment info + diagnostic-bundle download links.
- **Layout:** centered max-width 880 px Stack of three Cards: marketing summary, deployment Grid (8 fields incl. Node version, port, data dir, billing mode, key/bearer/session-secret presence Chips), download buttons row.
- **Source:** `src/app/(admin)/about/page.tsx`.

---

## 8. Component library

Beyond the MUI primitives, the console keeps a tiny first-party component layer. Everything else is a direct MUI usage.

### 8.1 `src/components/shell/`

- **`app-shell.tsx`** — `<AppShell title breadcrumb actions>` wraps every admin page. Permanent-variant `Drawer` rail (collapses to 80 px, expands to 256 px on hover); top sticky `AppBar` with breadcrumb + title + global-search trigger + page actions; main scrollable content. Owns the `⌘1`–`⌘0` accelerator and `⌘K` palette open. Uses `useColorScheme()` + a footer IconButton for theme toggle; another for logout.
- **`command-palette.tsx`** — `Dialog` containing a free-text TextField with adornments + a `List` of nav items. Filters case-insensitively; clicking pushes the route and closes.
- **`nav-items.ts`** — single source of truth for nav: `{href, label, icon, shortcut, section}[]`.
- **`nav-icon.tsx`** — tiny string-to-icon mapper used by the rail and command palette.

### 8.2 `src/components/snackbar-provider.tsx`

Wraps an MUI `Snackbar` + a queue. Exposes `useSnackbar()` returning `{push({message, action?})}` so pages don't change at the call site vs. the prior implementation. One snackbar visible at a time; pending pushes queue.

### 8.3 `src/components/kpi-card.tsx`

Card with overline label, large headline value, optional delta (color-keyed by tone: positive / negative / neutral), helper caption, and an optional 24-bucket sparkline rendered as inline SVG (stroke uses `var(--mui-palette-primary-main)`).

### 8.4 `src/components/launch-checklist.tsx`

`Card` with avatar (CheckCircle / Flag depending on completion), title + counter, then a `List` of items; each item is a `ListItemButton` rendered as `next/link`. Item indicators: numbered Avatar for unfinished, Check Avatar for done.

### 8.5 `src/components/markdown.tsx`

Wraps `react-markdown` with `remark-gfm`, `remark-math`, `rehype-katex`. `<a target="_blank">` is the only JSX override. All remaining styling is in `globals.css` under `.markdown-body`.

### 8.6 `src/theme/`

- `palette.ts` — light / dark `PaletteOptions`.
- `typography.ts` — `TypographyVariantsOptions` with the Roboto Flex stack.
- `components.ts` — `Components<Theme>` defaults / overrides.
- `index.ts` — `extendTheme({ cssVarPrefix: "mui", colorSchemes, shape, typography, components })`.

### 8.7 `src/app/providers.tsx`

`'use client'`. Hosts `AppRouterCacheProvider` (Emotion + SSR insertion) → `ThemeProvider` (with `defaultMode="system"`, `modeStorageKey="relay_theme"`) → `CssBaseline enableColorScheme`.

---

## 9. Technical architecture

### 9.1 Stack

| Layer | Library | Pin |
|---|---|---|
| Framework | Next.js | 15.5.x (App Router, RSC, server actions enabled with 32 MB body limit) |
| UI library | @mui/material | ^6.5 |
| MUI X (table) | @mui/x-data-grid | ^7.29 (MIT) |
| MUI X (date) | @mui/x-date-pickers | ^7.29 (wired but not yet user-visible) |
| MUI Next bridge | @mui/material-nextjs | ^6.5 |
| CSS-in-JS | @emotion/react + @emotion/styled + @emotion/cache | ^11.13–11.14 |
| Markdown | react-markdown + remark-gfm + remark-math + rehype-katex + katex | latest stable |
| State | React 19 hooks | — |
| Forms | Hand-rolled + `useState` | — |
| Date util | dayjs | ^1.11 |

Removed in this rewrite: tailwindcss, postcss, autoprefixer, tailwind-merge, lucide-react, the entire `src/components/m3/` primitive layer, `src/styles/m3-tokens.css`, `src/lib/cn.ts`.

### 9.2 Repo layout (frontend)

```
relay/
  src/
    app/
      layout.tsx               root html lang="zh-Hans" + InitColorSchemeScript + Providers + SnackbarProvider
      providers.tsx            client-side AppRouterCacheProvider + ThemeProvider + CssBaseline
      globals.css              minimal resets + .markdown-body styles + KaTeX import
      page.tsx                 root redirect (server component)
      login/page.tsx
      setup/page.tsx           server gate
      setup/setup-form.tsx     client Stepper
      (admin)/
        layout.tsx             session/setup gate (RSC)
        dashboard/page.tsx
        requests/page.tsx
        requests/conversations/[id]/page.tsx
        playground/page.tsx
        accounts/page.tsx
        accounts/[id]/page.tsx
        billing/page.tsx
        observability/page.tsx
        models/page.tsx
        settings/page.tsx
        docs/page.tsx
        about/page.tsx
    components/
      shell/{app-shell,command-palette,nav-items,nav-icon}.tsx
      snackbar-provider.tsx
      kpi-card.tsx
      launch-checklist.tsx
      markdown.tsx
    theme/{palette,typography,components,index}.ts
```

### 9.3 Build / deploy contract

- `npm run build` produces a Next.js standalone bundle under `relay/.next/standalone/`. `output: "standalone"` in `next.config.mjs` is the contract.
- The deploy artefact is a **tar of `(.next/standalone/* ⊕ .next/static ⊕ public)` mirroring the runtime layout**. On the EC2 host this lands in `/opt/aichat-relay/`, owned by `ubuntu:ubuntu`, and is started by `aichat-relay.service` (systemd) running `node /opt/aichat-relay/server.js`.
- Rollback strategy: prior `/opt/aichat-relay` is renamed to `/opt/aichat-relay.bak.<TS>` before each swap. To revert, stop the service, swap directories, restart.
- The console is reachable behind Caddy 2.11 at `https://ai.origenclub.cn`.

### 9.4 SSR / hydration contract

- `<html suppressHydrationWarning>` because `InitColorSchemeScript` mutates `data-mui-color-scheme` before React hydrates.
- `AppRouterCacheProvider` is **mandatory** — without it, Emotion injects styles after hydration and produces FOUC + class mismatches.
- The shell is a `'use client'` component. All admin pages may freely opt in to client (`'use client'`) when they need state / SSE; otherwise they remain RSC.

---

## 10. Quality requirements

### 10.1 Test layers

1. **Unit / integration (vitest, happy-dom for `tests/ui/`):** all under `tests/{unit,api,ui}/**`. Bootstrapped by `tests/setup.ts` which provides per-worker temp data dirs and an in-memory `next/headers` `cookies()` mock.
2. **E2E (vitest with separate `vitest.e2e.config.ts`):** boots a real `next start` once via `tests/e2e/global-setup.ts` and `server-fixture.ts`, then runs `tests/e2e/**/*.e2e.test.ts` over HTTP. Uses an isolated tmp data dir.
3. **Coverage (`npm run test:coverage`):** vitest v8 provider; threshold `≥ 70%` lines / statements / functions / branches. Server-rendered `(admin)/*/page.tsx` files are excluded because they only run in the Next runtime; they are exercised by the e2e suite.

### 10.2 Pre-merge bar

- `npm run typecheck` — 0 errors.
- `npm test` — full unit + integration suite green.
- `npm run test:e2e` — e2e suite green (requires `npm run build` first).
- `npm run build` — standalone bundle compiles, all routes generated.
- zh-Hans diff against merge base — no string regressions.
- For UI-affecting changes — at minimum a smoke test under `tests/ui/` exercising the change.

### 10.3 Deploy bar

- Pre-deploy: full test suite green locally.
- Deploy: tar bundle, scp, atomic dir swap (backup → install → restart), single `systemctl restart aichat-relay`.
- Post-deploy: `curl /api/health` returns `{ok: true}`; `curl /login` returns `200`; HTML contains a `MuiButton` class and zero `md-sys-color-*` artefacts.

---

## 11. Out-of-scope decisions and parking lot

| Topic | Decision |
|---|---|
| i18n framework | Out of scope. zh-Hans hard-coded. |
| MUI X Charts | Deferred. Observability bar charts stay inline SVG. |
| Multi-stacked snackbars (`notistack`) | Deferred. One-at-a-time queue is good enough. |
| Visual regression (Playwright + screenshots) | Deferred. Coverage by manual eyeball + UI smoke tests. |
| Mobile-first responsive overhaul | Deferred. ≥ 1024 px is the design target. |
| Pigment-CSS migration | Deferred. Pigment-CSS is alpha as of 2026-05; revisit when GA. |
| Material Design 3 (MUI Material U) | Deferred until MUI ships a stable M3 component library. |
| Self-service end-user portal | Out of scope. Console is operator-only. |

---

## 12. Glossary

- **Relay** — the Next.js gateway server (runtime) defined by `relay/`. The PRD subject.
- **Console / Admin Console** — the operator-facing UI surfaces under `relay/src/app/(admin)/` plus `/login` and `/setup`.
- **Bearer token** — `RELAY_BEARER_TOKEN` (master) plus admin-issued tokens stored in `settings.json`. Carried as `Authorization: Bearer <token>` on API requests.
- **Client key** — per-device key issued during activation; used by Watch / iOS clients (`rk_xxxxx`).
- **Account / Device / Key / Grant** — billing entities. See `lib/billing/types.ts`.
- **Activation code** — a one-shot redeemable code that creates an account + key on first use (offline activation flow).
- **Pairing token** — a short-lived token a paired iPhone hands to the Watch to bootstrap account membership.

---

## 13. References

- Source of truth: `relay/src/`.
- Theme: `relay/src/theme/`.
- Tests: `relay/tests/{unit,api,ui,e2e}/`.
- Build / deploy: `next.config.mjs` (`output: "standalone"`); `aichat-relay.service` on EC2; `docs/relay-server-setup.md` for the SSH-tunnel topology.
- Project conventions: `CLAUDE.md` at repo root.
