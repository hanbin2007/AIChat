# 客户端激活/授权层从零重写 — 设计

> 状态：待用户最终审阅。日期：2026-06-11。
> 范围：纯客户端重写，**服务端（线上 Next.js relay）为冻结的事实来源**。

## 1. 目标与背景

现有客户端激活/计费层（main 的单体 `ActivationBillingService` + `RelayAccountService` + 散落消费点）产生了一轮 39 个已确认 bug。本次从零重写，四个目标同时达成（用户全选）：

- **正确性与健壮性** — 客户端跟服务端对不上时报错而非静默出错。
- **架构与可维护性** — 拆掉上千行 god-object，分层、职责单一、可独立测试。
- **可测试性** — 核心逻辑为纯函数，能对真实服务端契约做契约测试。
- **功能语义重构** — 重新定义激活/计费的状态流转与离线/在线关系。

**已定的语义决策：**

1. **Relay 为唯一授权事实来源。** 离线激活码降级为"引导手段"：用码换取一个 relay 账户，之后日常授权全看 relay 账户状态。StoreKit 购买亦然。
2. **无网时：宽限期缓存。** 缓存上次成功的 relay 状态；离线期间凭缓存继续可用 N 天（可配）；超期且刷新失败才落只读。信用离线乐观扣减，联网后与服务端对账调谐。
3. **范围：** 手表核心引擎 + 手表激活 UI + iOS companion 激活 UI + Keygen app，全包。

## 2. 问题陈述：病根在消费侧

调查（见 `docs/activation-audit-2026-06.md` 与消费侧专项调查）确认：真正的结构病不在"取数/解码"，而在**客户端如何消费激活状态**。同一个逻辑问题"用户能不能发消息"被三套会打架的判据回答：

- `isReadOnlyMode`（`ActivationBillingService:212-233`）
- `activationFailureMessage(for:)`（`:554-596`，还额外按 model 许可判断）
- `canRetryLatestReply` / 各处 `isAIConfigured`（`ChatStore:1134` 等，混进无关的"relay 配置是否完整"）

加上三个独立真相源（离线 `activationState`、在线 `relayAccountStatus`、配置 `isAIConfigured`）被各 consumer 单独咨询，视图自己重算图标/文案/状态。8 条排序后的消费侧问题（HIGH：判据打架；MEDIUM：多真相源、双重 send 检查、relay 在线/离线只读矛盾、发送时不复检；LOW：视图重算、`isAIConfigured` 混淆、历史 backend mode 分支散落）均源于**消费侧没有单一决策出口**。

## 3. 架构

```
RelayClient        纯网络。HTTP/SSE、解码 DTO，不懂"授权"。
   ↓ DTO
RelayContract      Codable 契约类型。契约测试用线上抓的真实 JSON 夹具钉死。
   ↓ RelaySnapshot
EntitlementEngine  纯函数状态机 reduce(State, Event) -> State。零 IO、零副作用、100% 单测。
   ↓
EntitlementStore   ★唯一 @Observable 真相源★。编排 client/cache/engine，对外只暴露 decision +
   ↓ EntitlementDecision  estimatedCost(model)（计费率随快照一起持有，见 §4）。
Consumers          ChatStore / 所有 View。只读 decision，零重算。
   ↕ (镜像)
SyncBridge         WatchConnectivity。手表=授权权威；companion=只读镜像，收 decision 快照 +
                   relay pairing token（用于 iOS 原生请求）。见 §9。
```

**SyncBridge 方向铁律**：手表是授权权威，companion 不独立判断授权，只镜像手表推来的 `decision`（+ 一份 relay pairing token 以便 iOS 侧直接发请求）。companion 显示的 decision 带 `asOf` 时间戳；超过阈值显示"等待手表同步"，不自行解锁。

每个单元的"做什么/怎么用/依赖谁"清晰可答：

| 单元 | 做什么 | 依赖 |
|---|---|---|
| `RelayClient` | 发请求、解码 DTO、暴露 typed error | URLSession、`RelayContract` |
| `RelayContract` | 定义线协议 Codable 类型 + 容错解码 | 无（叶子） |
| `EntitlementEngine` | `reduce(state,event)->state` + `derive(state,now)->decision` | 无（纯函数） |
| `EntitlementCache` | 持久化 `EntitlementState`（带 schemaVersion + 迁移） | SwiftData/文件 |
| `EntitlementStore` | 编排：拉取→reduce→缓存→发布 decision | 上述全部 |
| `ChatStore`/Views | 读 `decision` 渲染、派发 Event | `EntitlementStore` |

## 4. 单一决策出口（消费侧根治的核心）

```swift
struct EntitlementDecision: Equatable {
    enum Capability: Equatable {
        case ready                      // 能发
        case readOnly(LockReason)       // 不能发，带原因
        case bootstrapping              // 正在换取/绑定，过渡态
    }
    var capability: Capability
    var availableModels: [ModelID]      // 可选 model 列表（见下"model 语义"）
    var credits: CreditView?            // 余额/宽限信息，UI 直接渲染
    var cta: ActionableCTA?             // 锁定时引导去哪：去激活中心/重输码/续费
}
```

**model 语义（修正自审查 #7）**：**Relay 模式无"每设备 model 许可名单"**——relay 只有 credit 预算与计费率，账户 active 且有 credit 即所有 catalog 内 model 可用。因此 `availableModels` = relay catalog 暴露的 model 集合（来自快照），而**不是**一份限制名单。旧离线 license 里的 `allowedModelIDs` 在 relay-唯一-真相源下不再作为日常门控（仅在尚未换取 relay 账户的极少数过渡场景参考）。picker 按 `availableModels` 列出可选项，因此不会出现"选到一个发不出去的 model"。

**计费率归属（修正自审查 #1 — 原 BLOCKER）**：每个 model 的 input/output/search 计费率随 `RelaySnapshot.catalog` 一起被 `EntitlementStore` 持有。`ChatStore` 发送时**不另寻数据源**，而是调用 `store.estimatedCost(model:, request:)` 拿到本地估算 `cost`，再 `dispatch(.messageConsumed(cost, now))`。计费率因此留在授权层内部，不从 decision 抽象里漏出去。注意：这只是**离线 UX 估算**；联网刷新时以服务端权威用量对账（§6）。

enum LockReason: Equatable {
    case noAccount, expired, exhausted, revoked,
         offlineGraceElapsed, needsOnlineExchange, platformNotConfigured
}
```

**两条铁律：**

1. **单一计算点。** `EntitlementDecision` 只在 `EntitlementStore`（经 `EntitlementEngine.derive`）算出一次。任何 consumer——输入框锁定、发送门、报错文案、状态卡图标、retry 能否点、model 过滤——**只读它，禁止自行判断**。
2. **平台配置与用户授权正交。** "平台配没配"（relay base URL / token 等，原 `isAIConfigured`）作为 `LockReason.platformNotConfigured` 统一进同一决策值，不再在 `send()` 里做两道独立检查、报错顺序不定。

**这两条如何消解 8 条问题：**

- 判据打架（HIGH）：只剩一个 `decision`，物理上无从打架。
- model 不许可矛盾：model picker 按 `decision.availableModels` 列出可选项（见下"model 语义"）——**选不到一个发不出去的 model**，"可编辑却一发就错"从类型上消失。
- 多真相源各自咨询（MEDIUM）：三源在 engine 内汇成 `State`，consumer 看不到原始子状态。
- 双重 send 检查、报错顺序不定（MEDIUM）：平台/授权正交 + 单一决策，一处出 CTA。
- 在线/离线只读矛盾（MEDIUM）：`bootstrapping` 是显式过渡态，带"去绑定"CTA，不再"锁着却提示去设置"。
- 视图重算（LOW）：`decision` 自带渲染所需一切，视图不再 switch 枚举。
- 历史 backend mode 分支散落（LOW）：direct 后端模式已移除；UI 不再感知后端模式。

## 5. 状态机

`EntitlementEngine` 为纯函数；时间通过 Event 里的 `now` 注入（可重放、可单测）。

**State（持久化于 `EntitlementCache`，带 schemaVersion — 根治审计"billing.json 无版本号"）：**

```swift
struct EntitlementState: Codable, Equatable {
    var account: RelaySnapshot?        // 上次成功的 relay 快照
    var lastVerifiedAt: Date?          // 上次成功刷新时刻 → 宽限期基准
    var localSpend: Int                // 离线乐观扣减累计 credits，待对账
    var pending: PendingBootstrap?     // 待换取的离线码/配对(无网时暂存，联网自动执行)
    var lastError: RelayHardFailure?   // 401/撤销等硬失败，立即影响 decision
    var schemaVersion: Int
}

// 明确定义(修正自审查 #6)：从 RelayAccountStatusResponse 投影出决策所需的最小集
struct RelaySnapshot: Codable, Equatable {
    var account: RelayAccountSummary   // state / source / creditExpiresAt
    var key: RelayKeySummary           // keyValue(凭证) / state
    var creditBalance: Int             // 由 grants 汇总得到的权威余额
    var catalog: RelayCatalog          // plans + 每 model 计费率(供 estimatedCost)
    // grants/device/recentUsage 仅在 UI 透明展示时按需保留，不参与 derive()
}

// 待执行的引导：覆盖两条 exchange 路径(修正自审查 #2b — 生产有 offline-code 与 paired-token 两路)
enum PendingBootstrap: Codable, Equatable {
    case offlineCode(OfflineCode)      // 本地 HMAC 离线码
    case pairedToken(PairingToken)     // 配对令牌(iOS→watch)
    var issuedAt: Date                 // 用于过期判断
}

enum RelayHardFailure: Codable, Equatable { case revoked, paused, accountMissing }
```

**`lastError` 清除语义（修正自审查 #2b/#6 — 防状态机死锁）**：任何成功的 `.relayRefreshed` 或 `.exchangeSucceeded` 事件**无条件清空 `lastError` 并刷新 `lastVerifiedAt`**。`lastError` 只由 `.relayRefreshFailed(硬失败)`/`.keyRevoked` 写入。即一次成功往返总能让被 401 误置的 `lastError` 解除。

**事件优先级（修正自审查 #2a — 竞态）**：若 `.relayRefreshed(active account)` 与 `pending` 同时存在，刷新成功**优先并清空 `pending`**（已经有访问权，无需再换码）。`pending` 仅在 `account==nil` 时驱动 `bootstrapping`。

**`pending` 过期**：`PendingBootstrap.issuedAt` 超过其类型有效期（离线码/配对令牌各自的 window）即丢弃并落 `readOnly(.noAccount)`，不会无限期挂着一个换不掉的码。

**Event：**

```
.relayRefreshed(RelaySnapshot, now)    // 成功拉到 relay 状态(权威)
.relayRefreshFailed(RelayError, now)   // 拉取失败(无网/超时/401撤销)
.offlineCodeEntered(OfflineCode)       // 用户输入离线码
.exchangeSucceeded(RelaySnapshot)      // 离线码换成 relay 账户
.messageConsumed(cost, now)            // 发送乐观扣减
.purchaseApplied(RelaySnapshot)        // StoreKit 购买/续订
.signedOut / .keyRevoked               // 清空
```

**派生顺序 `derive(state, now) -> decision`（一处、有序、穷尽）：**

```
0. lastError ∈ {revoked,paused}                      → readOnly(.revoked), cta=重输码
   (硬失败置顶，永远压过宽限期——撤销立即生效，见 §6)
1. platform 未配置                                    → readOnly(.platformNotConfigured)
2. account==nil && pending==nil                       → readOnly(.noAccount), cta=去激活
3. account==nil && pending!=nil                        → bootstrapping
4. account.creditExpiresAt 已过                         → readOnly(.expired), cta=续费
5. effectiveCredits<=0 (= creditBalance-localSpend)    → readOnly(.exhausted), cta=续费
6. now-lastVerifiedAt > graceWindow && 最近一次刷新失败   → readOnly(.offlineGraceElapsed), cta=联网
7. 否则                                                → ready(availableModels, creditsView)
```

分支 0 置顶是有意为之：硬失败（撤销/暂停）**永远优先于宽限期**，使审查 #2c/#3 指出的"宽限窗内忽略撤销"不会发生——只要客户端**已收到**撤销信号即立即只读。注意客户端**未收到**撤销（离线且尚未刷新到 401）时仍按缓存 `ready`，这是乐观语义的有意取舍，见 §6。

## 6. 离线宽限 + 乐观扣减对账

- **发消息**：`messageConsumed` 把 `cost` 累加进 `localSpend`，`effectiveCredits` 立即下降——UI 实时反映，无网也能连发至本地估算见底。
- **联网刷新成功**（`relayRefreshed`）：服务端 `credits` 为权威值，engine 用它覆盖 `account.credits` 并把 `localSpend` 清零（对账完成；服务端已按真实用量扣过，以服务端为准）。
- **`cost` 来源（修正自审查 #1）**：`cost` 由 `EntitlementStore.estimatedCost(model:,request:)` 用快照里的计费率本地估算，不引入第二数据源（见 §4）。
- **宽限期**：`graceWindow`（可配，默认 7 天）从 `lastVerifiedAt` 起算。窗口内即使持续无网仍 `ready`；超窗且刷新仍失败才落 `.offlineGraceElapsed`。
- **撤销 vs 宽限（修正自审查 #3c — 有意取舍，非 bug）**：客户端**已知**的撤销（收到 401 → `lastError`）由 derive 分支 0 立即只读，压过宽限。客户端**未知**的撤销（离线、尚未刷新到 401）在宽限窗内仍按缓存 `ready`——这是"宽限期缓存 + 乐观"语义的必然代价：服务端仍会拒绝实际请求，客户端下次联网刷新即收敛。spec 明确接受此窗口，不试图消除。
- **时钟偏移（修正自审查 #3a/#3b）**：宽限判断 `now - lastVerifiedAt` 用单调/本地时钟，易被改表绕过或误锁。缓解：(a) `creditExpiresAt`/到期判断以**服务端时间戳**为准而非本地推算；(b) 记录 `lastVerifiedAt` 时一并存 `bootTimeAnchor`，检测到时钟大幅倒退/前跳时以"刷新失败"保守处理而非直接判过期；(c) 改表只能缩短自己的宽限，无法延长授权（授权权威在服务端），故非安全风险，仅 UX 韧性。

**一次发送的数据流：**

```
View → ChatStore.send()
   → 读 store.decision；非 .ready 直接按 LockReason 出 CTA(不再两道检查)
   → RelayClient 流式；本地 dispatch(.messageConsumed)
   → 结束后台 dispatch relayRefresh → 成功则对账
```

`ChatStore` 不再持有/计算任何授权逻辑，只做 `decision` 消费者 + 事件派发者。

## 7. 错误处理

原则：**解码/网络/授权失败必须进入 `decision` 或 typed error，绝不静默吞**（根治审计 H1/H5 的 `try?` 静默清空）。

- `RelayClient` 暴露 typed `RelayError`：`.unauthorized(401)`、`.decodingFailed(detail)`、`.transport`、`.server(status,body)`。
- 解码失败 → `.decodingFailed`，记日志（os.Logger fault）并作为 `relayRefreshFailed` 进 engine，**不静默把 account 变 nil**。
- 401/撤销 → `.unauthorized` → `.keyRevoked` → `decision=readOnly(.revoked)`，并清本地 key。
- 未知服务端枚举值 → 容错解码为 `.unknown`，不让整块对象崩（保留 H5 修复精神）。
- 日期解码 → 同时接受毫秒/秒 ISO（保留 H1 修复精神）。

## 8. 测试策略

- **EntitlementEngine 纯函数单测**：覆盖全部 (State×Event) 转移与 8 条派生分支；宽限边界、对账、乐观扣减、撤销立即生效——零 IO、毫秒级、可穷尽。
- **契约测试**：从线上 relay 抓真实响应 JSON 存为夹具（bootstrap/status/catalog/purchase 各形态，含毫秒日期、各 enum 值、`{status:...}` 包裹与裸对象），断言 `RelayContract` 解码后 account/key **非 nil**（根治"测试用 Swift 编码器自造数据"的假绿）。
- **EntitlementStore 集成测**：用 mock `RelayClient` 驱动事件，断言 `decision` 序列。
- **消费侧回归**：针对 8 条问题各写一个"以前会矛盾、现在一致"的测试（如：离线 active + model 不许可 → picker 过滤且 decision 一致）。

## 9. 落地范围与组件

**新建（手表核心）：** `RelayClient`、`RelayContract`、`EntitlementEngine`、`EntitlementCache`、`EntitlementStore`。

**改写为薄消费者：** `ChatStore`（删除所有授权计算，改为读 `decision` + 派发 Event）、`ConversationDetailView`/`ConversationListView`/`ConversationSettingsView`/`ActivationCenterView`/`ActivationStatusCard`（只读 `decision`）。

**iOS companion（细化自审查 #5）：** `CompanionActivationCenterView` 改为读镜像来的 `decision`。`SyncBridge` 协议明确：手表是授权权威，发生 decision 变化或收到 companion 的拉取请求时，手表**推**一份 `{decision, asOf}` + 一个 relay pairing token（供 iOS 侧直接发请求）给 companion；companion **不独立判断授权**，只渲染镜像并在 `asOf` 过旧时显示"等待手表同步"。这正是现有 `shareManagedRelayAccessToCompanionIfPossible()` → `requestPairingToken()` → `pushRelayPairingToken()` 的职责，收编进 `SyncBridge` 单一通道，消除手表/companion 授权判断不一致。

**Keygen app：** 保留，语义不变（生成可换取 relay 账户的离线码）；对齐新 `OfflineCode`/exchange 契约。

**删除/收编：** 单体 `ActivationBillingService`、`RelayAccountService`、`RelayAccessRepository` 的授权职责并入新分层；离线 `OfflineActivation` 验证逻辑保留但仅服务于"输入码→exchange"，不再是独立授权真相。

## 10. 迁移 / 切换（重写自审查 #4/#8）

**数据迁移映射（`EntitlementCache` 首次加载执行一次，写 `schemaVersion=1`）：**

| 旧持久化 | 旧字段 | 新 `EntitlementState` | 规则 |
|---|---|---|---|
| `RelayAccessStateRecord` | `relayKeyValue` 非空 | `account` 留空 + 标记"需首刷" | 有 relay key → 启动即用该 key 拉 `/account/status` 重建 `RelaySnapshot`（权威值现取，不信旧缓存的余额/到期） |
| `ActivationStateRecord` | 离线 license（仅离线、无 relay key） | 见下"存量离线用户决策" | message-count 与 credit 不可换算（正交），不强行映射 |
| 旧 `usedMessageCount` | 离线已用消息数 | **不迁移** | 这是消息计数，relay 是 credit 计量；联网首刷后以服务端 credit 为准；丢弃旧计数 |

- **关键原则**：迁移**不信任旧缓存的余额/到期/状态**，只迁移"身份"（relay key / 待换码）；真实授权一律靠首次联网刷新重建。这天然规避旧 `billing.json` 无版本、字段漂移的问题。
- **key 存储**：`RelaySnapshot.key.keyValue` 沿用现有安全存储位置（Keychain / app-group，与现状一致），不改存储介质。

**存量"仅离线激活"用户（无 relay key）—— 已定 = 选项 B（直接要求重新激活）。** 升级后这类用户迁移为空态 → `decision = readOnly(.noAccount)`，引导重新输入码/购买。**因此新引擎不需要任何 legacy-offline 兜底分支，`derive()` 保持 §5 的形态。** 迁移代码对"无 relay key 的旧离线 license"不做转换，直接丢弃旧离线状态。

**切换方式（澄清自审查 #8 — 消除双读窗口）：**
- 新分层（`RelayClient`/`Contract`/`Engine`/`Cache`/`Store`）可**先各自独立合入并单测**，此阶段不接线、不被 `ChatStore` 读取，对运行无影响。
- 最后一步**原子接线**：同一次提交里，`ChatStore` 与所有 View 从旧 `ActivationBillingService` 切到 `EntitlementStore`，并删除旧服务的授权职责。**不存在两套同时供 `ChatStore` 读的中间状态**。
- `schemaVersion` 单调递增；旧版本读不到新 cache 时退回空态并触发首刷（不崩、不串数据）。

**构建验证**：每步保证 Watch App / iOS / Keygen 三目标编译 + 测试通过（沿用本仓库已验证的 known-good 模拟器）。

## 11. 非目标（本次不做）

- **契约代码生成（方案 B）**：暂用手写契约 + 真实 JSON 夹具防漂移；codegen 流水线待契约频繁变动再上。
- **离线纯本地授权**：已决策 relay 为唯一真相源，不保留"无 relay 账户也能凭本地码长期使用"。
- **服务端改动**：服务端冻结；本次不动 relay。
- App Attest（H4）、离线非对称签名（H2）、JWS 根证书启用（C2）——属另行的服务端/发布决策。

## 12. 已解决的关键决策

| 决策 | 选择 |
|---|---|
| 授权事实来源 | Relay 唯一真相源；离线码=引导 |
| 离线容忍 | 宽限期缓存 + 乐观扣减 + 联网对账 |
| 范围 | 手表核心 + 手表 UI + iOS companion + Keygen |
| 架构 | 方案 A（分层状态机 + 单一决策出口） |
| 契约防漂移 | 手写契约 + 真实 JSON 夹具契约测试（不上 codegen） |
| 消费侧 | 单一 `EntitlementDecision`；平台配置与授权正交 |

## 13. 已决策（自审查暴露的开放项）

1. **存量"仅离线激活"用户（无 relay key）的迁移 → 选定 B：直接要求重新激活。** 升级即空态 + `readOnly(.noAccount)`，引导重输码/购买。`derive()` 无需 legacy-offline 分支，状态机保持 §5 形态。（见 §10）

2. **`graceWindow` 默认值**：定 7 天，可后续调。

## 附：自审查处置记录

独立 agent 对抗式审查提出 3 个 BLOCKER + 若干 should-fix，处置如下：
- BLOCKER 计费率漏出 decision → §4 计费率随快照入 `EntitlementStore`，`estimatedCost()` 暴露，已修。
- BLOCKER `RelaySnapshot` 未定义 → §5 显式定义投影类型，已修。
- BLOCKER 迁移路径含糊 + message-count/credit 正交 → §10 重写为映射表 + "只迁身份不迁余额" 原则，已修。
- relay 无 per-device model 名单 → §4 修正 `availableModels` 语义，已修。
- `lastError` 清除/事件优先级/`pending` 过期 → §5 补全，已修。
- 撤销 vs 宽限竞态 + 时钟偏移 → §6 明确为有意取舍并给缓解，已修。
- companion 同步未定义 → §3/§9 补 `SyncBridge` 通道与方向铁律，已修。
- 存量仅离线用户迁移 → 升级为 §13 待你决策项。
