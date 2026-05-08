# Watch 客户端缺失功能补齐 —— 5 阶段路线图

## Context

`docs/watch-rewrite-missing-features.md` 列出 15 节、约 100 项缺失功能。前一次 PR (`claude/rewrite-apple-watch-client-CfNfP`) 把后端 / 持久化 / VM 骨架重写为 relay-only + 严格 per-VM MVVM,但功能等价度只到 ~40%:streaming pacer / auto-scroll / 后台续传 / completion 反馈 / send 重试 / 附件迁移 / 同步 / StoreKit 编排 / 几乎全部 UI 都缺。其中 **§11.1 / §12.1 / §5.1 三条**是上线阻塞,不修则装机即坏。

本计划目标:把 §1–§15 全部补回,**保留当前 per-VM 架构**(不复活 `ChatStore` 中央 store),按依赖顺序分 5 阶段交付,每个新增 VM/Service 配单元测试,关键 UI 状态有 `attachScreenshot` 截图,并重建 `MockChatService` + `UITestBootstrap` + `AIChat_UI_TEST_SCENARIO` 让 UI 测试可以跑。

**重要约束**:**不从 git 历史恢复任何旧实现**。所有被删除的文件(`StreamingTextPacer`、`ConversationAutoScrollController`、`TranscriptionCompletionFeedbackProvider`、`CompanionSyncBridge` 等)都按当前 per-VM + actor 架构**重新设计编写**,与新的 `ChatService` AsyncThrowingStream 输出 / `ConversationPersistence` actor / `@Observable` VM 范式对齐。旧文件名仅作功能定位参考,不复用代码。

---

## 架构决定(必须先落)

- 当前实际架构:`AIChat Watch App/Stores/` 下每 VM 一个 `@MainActor final class` + `@Observable`;`AppEnvironment` 注入服务;`ConversationPersistence` (actor) 通过 AsyncStream 作为单一真理源。**保留**这套,不复活 `ChatStore`。
- **修改 `CLAUDE.md`**:删除 "ChatStore is the sole `@StateObject`" 段落,改写"Architecture"小节描述 per-VM MVVM + AppEnvironment + ConversationPersistence。Phase 1 一并落地。
- 修改 `AIChat Watch App/AIChatApp.swift`:加入 `AIChat_UI_TEST_SCENARIO` 环境变量分支占位(实际 UITestBootstrap 在 Phase 5 实装)。

---

## 测试基础设施(贯穿,Phase 5 整体落地)

- 从 `ChatService` actor 抽出 `ChatServiceProtocol`(Phase 2 一并做),让 mock 实现可注入。
- 新增 `MockChatService`(可发可控 SSE 流、可注入失败和延迟),以及 `MockBillingService` / `MockSyncService`,放 `AIChat Watch AppUITests/Support/`。
- 新增 `AIChat Watch App/Support/UITestBootstrap.swift`,根据 `AIChat_UI_TEST_SCENARIO` 在 `AppEnvironment` 里替换 service 实现。
- 场景枚举:`empty` / `streaming` / `attachments_image` / `attachments_audio` / `error_retry` / `paired_companion` / `unpaired` / `aod_active` / `low_balance` / `heavy_markdown` / `formula_zoom` / `auto_scroll_interrupt`。
- 新增 `AIChat Watch AppUITests/UITestSupport.swift`:复刻 iOS 端 `attachScreenshot(_:named:)` 帮助函数。
- CI 流水线 `ci_scripts/ci_post_xcodebuild.sh` + `ui-screenshots*.yml` 已就绪,无需改动,只需测试在 `XCTAttachment` 里产出 PNG 即可被 ASC bridge 拾取。

---

## Phase 1 — 上线阻塞修复

**目标**:不修则装机即坏的三条 + 架构文档对齐。

修改:
- `AIChat Watch App/Stores/ActivationCenterViewModel.swift` —— `bootstrap()` 成功后调一次 `RelayKeyStore.set(_:appGroupIdentifier:)`(§11.1,~5 行)。
- `AIChat Watch App/Persistence/AIChatMigrationPlanV1ToV2.swift` —— 迁移时若 V1 attachment `data` 为空,从 sidecar `attachments/<id>.bin` 读回,再写入 V2 `AttachmentEntity.data`(§5.1)。
- `CLAUDE.md` —— 改写架构段。

新增:
- `AIChat Watch AppTests/Fixtures/V1Snapshot/` —— V1 sqlite + sidecar attachments 真 fixture(§12.1 前置)。
- `AIChat Watch AppTests/V1ToV2MigrationFixtureTests.swift` —— 跑迁移、断言所有数据 + 附件 blob 完整、重跑幂等(§12.1)。
- `AIChat Watch AppTests/ActivationCenterViewModelRelayKeyStoreTests.swift` —— 断言 `bootstrap()` 写入 RelayKeyStore(§11.1)。

依赖:无。

---

## Phase 2 — 流式 UX & 可靠性回归

**目标**:把用户立刻能感知的退化(stream 一次甩满屏 / 不自动滚 / 熄屏断流 / 失败不重试 / 无 haptic)全部补回。

新增(全部重新设计,**不引用 git 历史代码**):
- `AIChat Watch App/Services/StreamingTextPacer.swift` —— 新写一个 actor,输入是 `ChatService` 的 `AsyncThrowingStream<ConversationThread, Error>`,输出再转一层 `AsyncStream<ConversationThread>` 供 VM 消费,内部按 30Hz tick 自适应 reveal 字符;Phase 4 视图层订阅(§1.1)。
- `AIChat Watch App/Services/ConversationAutoScrollController.swift` —— 新写一个 `@MainActor` 状态机,SwiftUI `ScrollViewReader` 驱动;接收 stream 变化事件 + 用户滚动手势事件,产出"是否应自动滚到底"决策;识别同气泡内 vs 跨气泡(§1.2)。
- `AIChat Watch App/Services/BackgroundSessionCoordinator.swift` —— 新写,包 `WKExtendedRuntimeSession`,流式期间 begin / 完成 invalidate(§2.1)。
- `AIChat Watch App/Services/CompletionFeedbackProvider.swift` —— 新写,`WKInterfaceDevice.play(.success)` + UNUserNotification(§2.1 / §2.3)。

修改:
- `AIChat Watch App/Services/ChatService.swift` —— 抽出 `ChatServiceProtocol`;`send(...)` 内部包一层根据 `SettingsService.sendFailureRetryLimit` 退避重试(§2.2)。
- `AIChat Watch App/Stores/ConversationDetailViewModel.swift` —— 串接 pacer / autoscroll / background / haptic;send 失败状态与重试按钮。

新增测试:
- `StreamingTextPacerTests`、`ConversationAutoScrollControllerTests`、`BackgroundSessionCoordinatorTests`、`CompletionFeedbackProviderTests`、`ConversationDetailViewModelStreamingTests`(覆盖重试 / 取消 / pacer 注入)。

依赖:Phase 1 已完成。

---

## Phase 3 — 同步 & 计费 GA 阻塞

**目标**:跨设备同步 + StoreKit 编排走通。

新增(全部重新设计,**不引用 git 历史代码**):
- `AIChat Watch App/Services/iCloudSyncService.swift` —— 新写一个 actor,基于 `ConversationPersistence` AsyncStream 订阅本地变更 + CloudKit `CKDatabaseSubscription` 订阅远端变更,使用新 V2 schema 的 `DeletedTombstoneEntity` 做冲突解决(§3.1)。
- `AIChat Watch App/Services/CompanionSyncBridge.swift` —— 新写一个 actor,封装 `WCSession`,以新 `ConversationPersistence` API 为同步面;消息体用新 V2 实体的 Codable 投影,而非旧 V1 schema(§3.2)。
- `AIChat Watch App/Services/BillingPurchaseCoordinator.swift` —— 新写,`@MainActor` 持 `Product` 缓存,prepare → `Product.purchase(options:)` → submit 串联(§4.1)。
- `AIChat Watch App/Services/iPhonePurchaseFallbackService.swift` —— 新写,watchOS 受限时通过 `CompanionSyncBridge` 把购买请求转给 iPhone(§4.2)。
- `AIChat Watch App/Services/RestoreTransactionsScanner.swift` —— 新写,迭代 `Transaction.currentEntitlements` 重建本地状态(§4.3)。

修改:
- `Stores/RelayPurchaseSheetViewModel.swift` —— 用 `BillingPurchaseCoordinator` + `RestoreTransactionsScanner`。
- `Stores/RelayPairingTokenViewModel.swift` —— 通过 `CompanionSyncBridge` 把 pairing token 投递到 iPhone(§11.2)。
- `AppEnvironment.swift` —— 注册 4 个新 service。
- iOS Companion 端 `AIChatRegistrationApp.swift` —— 接收 `CompanionSyncBridge` 的 pairing / 购买事件。

新增测试:
- `iCloudSyncServiceTests`、`CompanionSyncBridgeTests`、`BillingPurchaseCoordinatorTests`、`iPhonePurchaseFallbackServiceTests`、`RestoreTransactionsScannerTests`。

依赖:Phase 1(迁移)、Phase 2(`ChatServiceProtocol` 抽取范式复用)。

---

## Phase 4 — UI 重设计、设计系统、语音、记忆、工具、AOD、设置

**目标**:把 PlaceholderShell 之外的可见表面全部还原 / 重做。

新增:
- `AIChat Watch App/DesignSystem/` —— `Tokens.swift`、`Typography.swift`、`Components/`(§9.5)。
- `AIChat Watch App/Views/` 下:
  - `ConversationDetailView.swift` + `MessageBubbleView.swift` + `AttachmentView.swift`(消费 `MarkdownView` + `swiftui-math`,接 pacer / autoscroll / RenderBudget / Normalizer)(§1.3 / §1.4 / §9.2 / §9.6)。
  - `ConversationListView.swift`(收藏过滤 / 搜索 / 删除确认 / 最近消息预览)(§9.1)。
  - `FavoritesView.swift`、`PromptLibraryView.swift`(§9.3)。
  - `ConversationSettingsView.swift`(focus / pinned memory / archive / tools toggle 编辑)(§6.2 / §7.1)。
  - `GlobalSettingsView.swift`(transcription / send retry / auto-scroll Form)(§13)。
  - `ActivationCenterView.swift`(在线/离线激活 + fingerprint 显示 + 状态卡片)(§11.3 / §9.4)。
  - `Components/RelayStatusDot.swift`、`ConfigurationBannerView.swift`、`ActivationStatusCard.swift`(§9.4)。
- `AIChat Watch App/Views/VoiceRecordingView.swift` + `Stores/VoiceRecordingViewModel.swift` —— 新写录音状态机 / 倒计时 / 录音按钮,接现有 `VoiceRecorder` → `TranscriptionService`(§8.1 / §8.2,**不复用旧 `VoiceRecordingHelper.swift`**)。
- `AIChat Watch App/Stores/GlobalPinnedMemoryViewModel.swift`(§6.3)。
- `AIChat Watch App/Services/AlwaysOnDisplayCoordinator.swift` —— 新写,消费现有 `WatchDisplayStateMonitor`,AOD 时折叠敏感内容(§14,**不复用旧 `WatchDisplayStateObserver` 视图**)。

修改:
- `Stores/ConversationSettingsViewModel.swift` —— 暴露 `setFocusState` / `addMemoryItem` / `removeMemoryItem` / `addPinnedMemory` / `setUsesGoogleSearch` / `setUsesCodeExecution`(§6.2 / §7.1)。
- `Stores/ConversationDetailViewModel.swift` —— `done` 事件后异步触发 `MemoryService.refreshArtifacts(...)`,merge 回 thread upsert(§6.1);消费 `AlwaysOnDisplayCoordinator`。
- `Views/PlaceholderShell.swift` —— 重命名为 `RootShellView.swift`,内部从占位换成实视图。

新增测试:
- VM 单测:`VoiceRecordingViewModelTests`、`GlobalPinnedMemoryViewModelTests`、扩展 `ConversationSettingsViewModelTests`(focus / memory / tools toggle)、扩展 `ConversationDetailViewModelTests`(memory refresh)。
- `AlwaysOnDisplayCoordinatorTests`。

依赖:Phase 2(streaming / autoscroll / RenderBudget)、Phase 3(billing / sync)。

---

## Phase 5 — 测试基础设施 & UI 测试矩阵

**目标**:Mock streaming + UITestBootstrap + 一整套带截图的 UI 测试。

新增 / 修改(测试基础设施段已列):
- `AIChat Watch AppUITests/Support/MockChatService.swift`、`MockBillingService.swift`、`MockSyncService.swift`。
- `AIChat Watch App/Support/UITestBootstrap.swift`、`AIChat Watch AppUITests/UITestSupport.swift`(`attachScreenshot`)。
- `AIChat Watch App/AIChatApp.swift` —— 完成 `UITestBootstrap` 接线。

新增 UI 测试(每个测试关键状态调 `attachScreenshot`):
- `ConversationStreamingUITests`(formula_zoom、heavy_markdown、streaming_scroll_performance、streaming_stress、auto_scroll_interrupt、touch_scroll、reply_completion_anchor)。
- `ConversationListUITests`(list_scroll_performance、conversation_navigation、conversation_delete_persistence)。
- `BackgroundReplyUITests`(background_reply_notification —— 需 mock 后台续传)。
- `LatestMessageExpandedUITests`、`LatestThoughtSummaryCollapsedUITests`。
- `ToolEntryUITests`(§7.1 toggle UI)。
- `VoiceFlowUITests`(§8 录音状态机)。
- `BillingUITests`、`ActivationCenterUITests`、`SettingsUITests`、`AlwaysOnDisplayUITests`。
- 保留 `LaunchSmokeTests`。

依赖:Phase 4(视图需先存在)、Phase 2(`ChatServiceProtocol`)。

---

## 关键文件清单

代码:
- `AIChat Watch App/Stores/ActivationCenterViewModel.swift`、`ConversationDetailViewModel.swift`、`ConversationSettingsViewModel.swift`、`RelayPurchaseSheetViewModel.swift`、`RelayPairingTokenViewModel.swift`
- `AIChat Watch App/Services/ChatService.swift`、`MemoryService.swift`、`VoiceRecorder.swift`、`TranscriptionService.swift`、`WatchDisplayStateMonitor.swift`、`RelayKeyStore.swift`、`AppConfiguration.swift`
- `AIChat Watch App/Persistence/AIChatMigrationPlanV1ToV2.swift`、`ConversationPersistence.swift`、`AIChatSchemaV2.swift`
- `AIChat Watch App/Models/ChatModels.swift`(`ConversationHistoryRenderBudget` / `AssistantMessageContentNormalizer` / `RenderSignature` 三类要在 Phase 4 接到视图)
- `AIChat Watch App/Views/PlaceholderShell.swift`(Phase 4 改名 + 替换)
- `AIChat Watch App/AIChatApp.swift`、`AppEnvironment.swift`
- `Packages/MarkdownView`、`Packages/swiftui-math`(Phase 4 重新被消费)

文档 / CI:
- `CLAUDE.md`(Phase 1 同步架构改动)
- `ci_scripts/ci_post_xcodebuild.sh`、`.github/workflows/ui-screenshots-bridge.yml`、`ui-screenshots.yml`(无需改,仅验证 Phase 5 截图被拾取)

**不复用 git 历史代码**:旧 `StreamingTextPacer.swift`、`ConversationAutoScrollController.swift`、`TranscriptionCompletionFeedbackProvider.swift`、`CompanionSyncBridge.swift`、`VoiceRecordingHelper.swift`、`ConversationToolSettingsHelper.swift` 等仅作功能定位参考,实装时全部按当前 actor + `@Observable` VM + AsyncStream 范式从零编写。

---

## 验证方案

**单测**(每阶段 PR 必跑):
```
xcodebuild -scheme "AIChat Watch App" \
  -destination "platform=watchOS Simulator,id=93A83695-2859-4388-B337-957616D03F55" \
  test
```
重点断言:Phase 1 `V1ToV2MigrationFixtureTests` 跑过 + 幂等;Phase 2 pacer / autoscroll / retry / background coordinator;Phase 3 同步 actor + StoreKit coordinator;Phase 4 各 VM 行为。

**UI 测试 + 截图**:
```
xcodebuild -scheme "AIChat Watch UITests" \
  -destination "platform=watchOS Simulator,id=93A83695-2859-4388-B337-957616D03F55" \
  test
```
Xcode Cloud 触发后,`ci_post_xcodebuild.sh` 拾取 `XCTAttachment` PNG,`ui-screenshots-bridge.yml` 派发 `ui-screenshots.yml` 把截图回贴到 PR。**每个 UI 影响改动必须在对应 UI 测试里调 `attachScreenshot`**(CLAUDE.md 已强制此约定)。

**手动实机验证**(Phase 1 / 2 / 3 各一次):
- Phase 1:全新装机 → 完成激活 → kill app → 再次启动应直接联通 relay(§11.1);带 V1 数据库的旧设备升级到 V2,所有附件可见(§5.1 / §12.1)。
- Phase 2:发长回复 → 字符级 reveal 平滑、auto-scroll 跟进、用户上滑应冻结自动滚;息屏 5s 应继续接收 stream,完成时震动 + 通知(§1 / §2)。
- Phase 3:两台同 Apple ID 设备会话 / pinned memory 互相同步;watchOS 受限时 iPhone 完成购买后 watch 余额刷新(§3 / §4)。
- Phase 4:语音录入、tools 开关、focus / memory / archive 编辑、AOD 隐私折叠均按预期工作。
- Phase 5:CI 上 Watch UI 测试套全绿,PR 评论里有完整截图集合。
