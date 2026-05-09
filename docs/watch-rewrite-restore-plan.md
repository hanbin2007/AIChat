# Watch 客户端缺失功能补齐 —— 5 阶段路线图

## Context

`docs/watch-rewrite-missing-features.md` 列出 15 节、约 100 项缺失功能。前一次 PR (`claude/rewrite-apple-watch-client-CfNfP`) 把后端 / 持久化 / VM 骨架重写为 relay-only + 严格 per-VM MVVM,但功能等价度只到 ~40%:streaming pacer / auto-scroll / 后台续传 / completion 反馈 / send 重试 / 同步 / StoreKit 编排 / 几乎全部 UI 都缺。其中 **§11.1** 是上线阻塞,不修则装机即坏。

本计划目标:把 §1–§15 全部补回,**保留当前 per-VM 架构**(不复活 `ChatStore` 中央 store),按依赖顺序分 5 阶段交付,每个新增 VM/Service 配单元测试,关键 UI 状态有 `attachScreenshot` 截图,并重建 `MockChatService` + `UITestBootstrap` + `AIChat_UI_TEST_SCENARIO` 让 UI 测试可以跑。

**重要约束**:
- **不从 git 历史恢复任何旧实现**。所有被删除的文件(`StreamingTextPacer`、`ConversationAutoScrollController`、`TranscriptionCompletionFeedbackProvider`、`CompanionSyncBridge` 等)都按当前 per-VM + actor 架构**重新设计编写**,与新的 `ChatService` AsyncThrowingStream 输出 / `ConversationPersistence` actor / `@Observable` VM 范式对齐。旧文件名仅作功能定位参考,不复用代码。
- **不迁移 V1 旧用户数据**。原 §5.1(附件 sidecar 迁移)与 §12.1(V1→V2 迁移测试)从计划中**移除**;`Persistence/AIChatMigrationPlanV1ToV2.swift` 视作**死代码,在 Phase 1 删除**,V2 schema 直接当作首次安装的初始 schema。升级路径通过版本提醒用户清空旧数据 / 重装,不做兼容。

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

## Phase 1 — 上线阻塞修复 + 死代码清理(详细)

**目标**:RelayKeyStore 写回(§11.1)+ 删除已弃用的 V1 迁移层 + `CLAUDE.md` 架构对齐。

### 1.1 RelayKeyStore 写回(§11.1)

文件:`AIChat Watch App/Stores/ActivationCenterViewModel.swift` (lines 38–46 为 `bootstrap()`,lines 60–82 为 `redeemOffline(...)`)。

变更:
- VM init 新增参数:`init(service: RelayActivationService, appGroupIdentifier: String?)`,VM 持 `private let appGroupIdentifier: String?`。
- 新增私有方法:
  ```swift
  private func persistBearerKey(from response: RelayAccountStatusResponse) {
      RelayKeyStore.set(response.key?.keyValue, appGroupIdentifier: appGroupIdentifier)
  }
  ```
  (`RelayKeyStore` 定义在 `AIChat Watch App/Services/AppConfiguration.swift:155–179`,签名:`static func set(_ key: String?, appGroupIdentifier: String?)`。)
- `bootstrap()` 中 `status = try await service.bootstrap()` **之后**立即 `persistBearerKey(from: status!)`。
- `redeemOffline(...)` 中 `status = try await service.exchangeOffline(...)` 之后同样调用(offline 兑换换发 key)。
- `refreshStatus()` **不写**(纯账户余额刷新,不应改 key)。
- 调用方更新:目前 VM 唯一构造点在 `ActivationCenterViewModelTests.swift`(无生产 view 构造方,Phase 4 才接);测试更新见 1.2。

### 1.2 RelayKeyStore 单元测试(§11.1)

新增:`AIChat Watch AppTests/ActivationCenterViewModelRelayKeyStoreTests.swift`

模式参考 `ActivationCenterViewModelTests.swift`(用 `MockBillingNetworking` + `RelayBillingFixtures.accountStatus(creditBalance:keyValue:)`)。每个 case 用唯一 suite 名 `"AIChat.tests.\(UUID())"` 隔离 UserDefaults。

测试用例:
- `test_bootstrap_writesBearerKeyToRelayKeyStore` — bootstrap 成功后 `RelayKeyStore.load(appGroupIdentifier:) == "rk_new"`
- `test_bootstrap_failureLeavesStoreUntouched`
- `test_redeemOffline_writesRotatedBearerKey`
- `test_refreshStatus_doesNotMutateStore`
- `tearDown` 清理:`UserDefaults().removePersistentDomain(forName: suite)`

### 1.3 删除迁移层

删除整文件:
- `AIChat Watch App/Persistence/AIChatMigrationPlanV1ToV2.swift`(312 行)
- `AIChat Watch App/Services/ConversationStoreModels.swift`(V1 SwiftData 实体,仅供迁移消费:`ConversationRecord` / `ConversationMessageRecord` / `ConversationAttachmentRecord` / `ConversationMemoryRecord` / `ConversationPinnedMemoryRecord` / `ConversationArchiveSegmentRecord` / `GlobalPinnedMemoryRecord` / `PromptPresetRecord` / `DeletedConversationTombstoneRecord` / `ConversationStoreMetadataRecord`)

修改 `AIChat Watch App/AppEnvironment.swift`:
- 删 line 38 字段 `let migrationOutcome: AIChatMigrationPlanV1ToV2.Outcome?`
- 删 `private struct ContainerBuildResult { let container: ModelContainer?; let outcome: AIChatMigrationPlanV1ToV2.Outcome? }`(line 130–134)→ `buildContainer` 直接返回 `ModelContainer?`
- 删 line 143 `let outcome = AIChatMigrationPlanV1ToV2.migrateIfNeeded(v2Container: container, rootURL: rootURL)`
- 删 `private static func resolvedStorageRoot(configuration:)`(仅 migration 用)
- `init` 内所有 `migrationOutcome` 引用清掉
- `buildContainer` 简化为:
  ```swift
  private static func buildContainer(configuration: AppConfiguration) -> ModelContainer? {
      try? AIChatModelContainer.makeOnDisk(appGroupIdentifier: configuration.appGroupIdentifier)
  }
  ```

确认无残留:
```
grep -RnE 'AIChatMigrationPlanV1ToV2|migrationOutcome|migrateIfNeeded|ConversationStoreModels|\bConversationRecord\b|\bConversationMessageRecord\b|\bConversationAttachmentRecord\b|\bConversationMemoryRecord\b|\bConversationPinnedMemoryRecord\b|\bConversationArchiveSegmentRecord\b|\bGlobalPinnedMemoryRecord\b|\bPromptPresetRecord\b|\bDeletedConversationTombstoneRecord\b|\bConversationStoreMetadataRecord\b' "AIChat Watch App" "AIChat Watch AppTests"
```
应 0 hit。

### 1.4 修改 `CLAUDE.md`

文件:`/home/user/AIChat/CLAUDE.md`

替换 `## Architecture` 段:
- 删 `**MVVM with a single central ObservableObject store.**`
- 删 `- ChatStore (\`AIChat Watch App/ViewModels/ChatStore.swift\`) is the sole \`@StateObject\` source of truth, injected via \`.environmentObject()\` from the \`@main\` app entry point`
- 删 `- Views read from and send actions to ChatStore; they never talk to services directly`
- 改写为:
  ```
  **Per-VM MVVM.**
  
  - Each screen has its own `@MainActor final class` + `@Observable` ViewModel under `AIChat Watch App/Stores/` (e.g. `ConversationDetailViewModel`, `ConversationListViewModel`, `ActivationCenterViewModel`, `RelayPurchaseSheetViewModel`).
  - `AppEnvironment` (`AIChat Watch App/AppEnvironment.swift`) is the composition root — it owns the `RelayAPIClient` actor and domain services (`ChatService`, `MemoryService`, `TranscriptionService`, `ConversationPersistence`, `SettingsService`, `RelayKeyStore`) and is injected into the SwiftUI view tree via `.environment(\.appEnvironment, ...)`. It does NOT hold ViewModels or shared UI state.
  - Views construct their own VMs from injected services on navigation; no central `ChatStore`.
  - The `ConversationPersistence` actor (under `Persistence/`) is the single source of truth for conversation data; subscribers receive change notifications via `stream() -> AsyncStream<[ConversationThread]>`.
  ```
- 替换 `**ViewModels/** — \`ChatStore\` only` → `**Stores/** — per-screen ViewModels listed above`

### 1.5 验证

```
xcodebuild -scheme "AIChat Watch App" \
  -destination "platform=watchOS Simulator,id=93A83695-2859-4388-B337-957616D03F55" \
  test
```
- 现有测试套全绿(确认删除迁移层不影响 `ConversationPersistenceTests` / `ActivationCenterViewModelTests` 等)
- 新增 `ActivationCenterViewModelRelayKeyStoreTests` 全绿
- 全新装机模拟器启动 → V2 store 直接生成,无 V1 残留依赖

依赖:无。

---

## Phase 2 — 流式 UX & 可靠性回归(详细)

**目标**:字符级 reveal(§1.1)+ 自动滚锚定(§1.2)+ 后台续传(§2.1)+ Send 重试(§2.2)+ Completion 触觉/通知(§2.3)。所有新增 actor/类按当前 `@Observable` per-VM + actor 范式编写,不复用 git 历史代码。

> 现有 `ChatService.send(...)` 已是 `nonisolated func ... -> AsyncThrowingStream<ConversationThread, Error>`(`AIChat Watch App/Services/ChatService.swift:45`),每次 SSE 事件 `yield` 一次完整 `ConversationThread` 快照。`ConversationDetailViewModel.send(text:attachments:)`(`AIChat Watch App/Stores/ConversationDetailViewModel.swift:76–94`)直接 `for try await update in stream { self.conversation = update }`。下方所有改动以此为基线。

### 2.1 抽出 `ChatServiceProtocol`(共享前置)

修改:`AIChat Watch App/Services/ChatService.swift`

新增协议(同文件顶部):
```swift
protocol ChatServiceProtocol: Sendable {
    nonisolated func send(
        userText: String,
        attachments: [ChatAttachment],
        to conversation: ConversationThread
    ) -> AsyncThrowingStream<ConversationThread, Error>
}
extension ChatService: ChatServiceProtocol {}
```

修改:
- `AIChat Watch App/Stores/ConversationDetailViewModel.swift` 字段 `let chatService: ChatService` → `let chatService: any ChatServiceProtocol`
- `AIChat Watch App/AppEnvironment.swift` 字段 `let chatService: ChatService?` → `let chatService: (any ChatServiceProtocol)?`

(用途:Phase 5 mock 注入 + 2.2 retry 包装。)

### 2.2 `RetryingChatService` —— Send 重试(§2.2)

新增:`AIChat Watch App/Services/RetryingChatService.swift`

```swift
actor RetryingChatService: ChatServiceProtocol {
    struct RetryPolicy: Sendable {
        let maxAttempts: Int          // 1...10, 来自 SettingsService.sendFailureRetryLimit (默认 3)
        let initialDelayNanos: UInt64 // 默认 2_000_000_000 (2s)
        let factor: Double            // 默认 2.0 → 序列 2s,4s,8s,...
    }

    private let inner: any ChatServiceProtocol
    private let policyProvider: @Sendable () async -> RetryPolicy
    private let sleeper: @Sendable (UInt64) async -> Void  // 默认包 Task.sleep,测试可替换

    nonisolated func send(...) -> AsyncThrowingStream<ConversationThread, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let policy = await policyProvider()
                var attempt = 0
                while true {
                    attempt += 1
                    var yieldedAny = false
                    do {
                        let upstream = inner.send(userText:..., attachments:..., to:...)
                        for try await snapshot in upstream {
                            yieldedAny = true
                            continuation.yield(snapshot)
                        }
                        continuation.finish()
                        return
                    } catch {
                        if yieldedAny || attempt >= policy.maxAttempts {
                            continuation.finish(throwing: error)
                            return
                        }
                        let delay = UInt64(Double(policy.initialDelayNanos) * pow(policy.factor, Double(attempt - 1)))
                        await sleeper(delay)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

关键约束:
- **重试只覆盖"未收到任何 yield 前"的失败**(网络拒绝 / TLS / DNS / 401)。一旦上游 yield 过任意快照(用户消息 + assistant placeholder 已落库,UI 已显示),错误直接透传 → VM 走 `.failed`,用户手动重试。这避免了"已落库 placeholder 被重试覆盖"的乱序。
- 退避:2s → 4s → 8s。
- `policyProvider` 闭包让上限实时反映 `SettingsService.sendFailureRetryLimit`(默认 3,clamp [1,10])。

`AppEnvironment.init` 改:
```swift
let core = ChatService(api: client, persistence: conversations, defaultModel: configuration.geminiModel)
self.chatService = RetryingChatService(
    inner: core,
    policyProvider: { @Sendable [settingsService] in
        await MainActor.run {
            .init(maxAttempts: settingsService.sendFailureRetryLimit,
                  initialDelayNanos: 2_000_000_000, factor: 2.0)
        }
    },
    sleeper: { try? await Task.sleep(nanoseconds: $0) }
)
```

测试:`AIChat Watch AppTests/RetryingChatServiceTests.swift`
- `test_passesThroughOnFirstAttemptSuccess`
- `test_retriesOnPreYieldFailure_thenSucceeds`
- `test_doesNotRetryAfterFirstYield`(yield 一次后抛错 → 只调用一次 inner)
- `test_throwsAfterExhaustingAttempts`
- `test_respectsExponentialBackoff`(注入 fake sleeper 记录 nanos → 断言 `[2e9, 4e9]`)
- `test_taskCancellationStopsRetry`

### 2.3 `StreamingTextPacer` —— 字符级 reveal(§1.1)

新增:`AIChat Watch App/Services/StreamingTextPacer.swift`

```swift
actor StreamingTextPacer {
    struct Configuration: Sendable {
        let tickInterval: Duration       // 默认 .milliseconds(33) ≈ 30Hz
        let baseCharsPerTick: Int        // 默认 4
        let maxCharsPerTick: Int         // 默认 24
        let backlogScale: Double         // 默认 0.25 → reveal = clamp(base, max, base + backlog * scale)
    }

    private let configuration: Configuration
    private let clock: any Clock<Duration>

    init(configuration: Configuration = .default, clock: any Clock<Duration> = ContinuousClock())

    nonisolated func pace(
        _ upstream: AsyncThrowingStream<ConversationThread, Error>
    ) -> AsyncThrowingStream<ConversationThread, Error>
}
```

行为:
- 内部维护 `latestUpstream: ConversationThread?`、`revealedTextLength: Int`、`revealedThoughtLength: Int`、`lastAssistantID: UUID?`。
- 上游每次 yield 把快照存到 `latestUpstream`,**不立刻**下游 yield。
- Tick 任务(每 `tickInterval`):
  1. 读 `latestUpstream`,定位最后一个 assistant message。
  2. 若 `lastAssistantID` 变化 → 重置 reveal 长度计数。
  3. 计算 backlog = `assistant.text.count - revealedTextLength`。
  4. 本 tick reveal = `min(maxCharsPerTick, max(baseCharsPerTick, baseCharsPerTick + Int(Double(backlog) * backlogScale)))`。
  5. 推进 `revealedTextLength`,thought 同样处理。
  6. 构造下游快照:`assistant.text` 截到 `revealedTextLength`(以 `Character` 索引,grapheme-safe);`thoughtSummary` 同样截。`modelResponseParts` / `attachments` / `status` 不动。
  7. yield 该快照。
- 上游 status 翻 `.sent`(`done` 事件):继续 tick 排空剩余字符;排空后 yield 一次完整上游快照(`status: .sent` + `modelResponseParts` 全量到位)→ `continuation.finish()`。
- 上游 throw → `continuation.finish(throwing:)`(不再 reveal 残留,避免把字符贴到 `.failed` 消息)。
- `modelResponseParts` 不做字符级 pacing(结构化代码块 / 工具结果整块出现)。
- 下游 `onTermination` → 取消 tick task + 取消上游订阅。

测试:`AIChat Watch AppTests/StreamingTextPacerTests.swift`(自写最小 `TestClock`)
- `test_holdsBackTextUntilTick`
- `test_revealsAtConfiguredRate`
- `test_drainsRemainingCharsAfterStreamCompletes`
- `test_emitsFinalSnapshotWithModelPartsAndStatusSent`
- `test_resetsRevealCountWhenAssistantMessageIDChanges`
- `test_propagatesUpstreamErrorWithoutRevealingPartial`
- `test_handlesMultiByteCharactersWithoutSlicingMidGrapheme`
- `test_cancellationStopsTickTask`

### 2.4 `ConversationAutoScrollController` —— 自动滚锚定(§1.2)

新增:`AIChat Watch App/Stores/ConversationAutoScrollController.swift`

```swift
@MainActor
@Observable
final class ConversationAutoScrollController {
    private(set) var anchorMessageID: UUID?
    private(set) var shouldFollow: Bool = true
    private var lastKnownLastMessageID: UUID?

    func messageContentDidUpdate(latestMessageID: UUID)
    func userDidInteractWithScroll()
    func streamDidFinish()
    func resetForNewConversation()
}
```

行为:
- `messageContentDidUpdate(latestMessageID:)`:
  - 若 `latestMessageID != lastKnownLastMessageID`(新气泡):无条件 `anchorMessageID = latestMessageID`,`shouldFollow = true`。这覆盖"用户冻结过自动滚 → 新一轮回复仍强制锚定"。
  - 否则若 `shouldFollow == true`:`anchorMessageID = latestMessageID`(同气泡内增量,SwiftUI 即使 anchor id 相同也会重计算到底位置)。
  - 否则:no-op。
- `userDidInteractWithScroll()`:`shouldFollow = false`(冻结)。
- `streamDidFinish()`:`shouldFollow = true`(回到就绪)。
- `resetForNewConversation()`:全部清零。

视图层(Phase 4 实装):`ScrollViewReader { proxy in ... .onChange(of: autoScroll.anchorMessageID) { _, id in if let id { proxy.scrollTo(id, anchor: .bottom) } } }`。手动滚动:`.simultaneousGesture(DragGesture(minimumDistance: 1).onChanged { _ in autoScroll.userDidInteractWithScroll() })`。

测试:`AIChat Watch AppTests/ConversationAutoScrollControllerTests.swift`
- `test_initialState`
- `test_messageUpdateMovesAnchor_whenFollowing`
- `test_messageUpdateIgnored_whenUserScrolled`
- `test_newMessageForcesAnchorEvenWhenFrozen`
- `test_streamFinishReArmsFollow`
- `test_resetForNewConversationClearsAllState`

### 2.5 `BackgroundSessionCoordinator` —— 后台续传(§2.1)

新增:`AIChat Watch App/Services/BackgroundSessionCoordinator.swift`

```swift
protocol BackgroundSessionHandle: AnyObject {
    func start()
    func invalidate()
    var delegate: WKExtendedRuntimeSessionDelegate? { get set }
}

@MainActor
final class BackgroundSessionCoordinator: NSObject {
    private let factory: @MainActor () -> BackgroundSessionHandle
    private var current: BackgroundSessionHandle?

    init(factory: @escaping @MainActor () -> BackgroundSessionHandle = { WKExtendedRuntimeSessionAdapter() })

    func begin()  // 幂等;若 current != nil 直接 return
    func end()    // current?.invalidate(); current = nil
}

#if os(watchOS)
private final class WKExtendedRuntimeSessionAdapter: NSObject, BackgroundSessionHandle, WKExtendedRuntimeSessionDelegate {
    private let session = WKExtendedRuntimeSession()
    var delegate: WKExtendedRuntimeSessionDelegate?
    func start() { session.delegate = self; session.start() }
    func invalidate() { session.invalidate() }
}
#endif
```

注:
- `WKExtendedRuntimeSession()` 默认即可拉一个通用后台会话(几分钟时长),不需要 Info.plist 额外 `WKBackgroundModes`。
- `didInvalidateWith` 时清 `current`,避免下次 begin 错以为还活着。

集成:
- `AppEnvironment` 增加 `let backgroundSession: BackgroundSessionCoordinator = BackgroundSessionCoordinator()`(单例)。
- VM `send(...)` 进入 task 时 `backgroundSession.begin()`,`defer { backgroundSession.end() }`。

测试:`AIChat Watch AppTests/BackgroundSessionCoordinatorTests.swift`(注 mock handle)
- `test_beginCreatesAndStartsSession`
- `test_beginIsIdempotentWhileActive`
- `test_endInvalidatesSession`
- `test_endIsNoOpWhenInactive`
- `test_didInvalidateClearsCurrent_allowsRebegin`

### 2.6 `CompletionFeedbackProvider` —— 完成触觉/通知(§2.3 / §2.1 通知部分)

新增:`AIChat Watch App/Services/CompletionFeedbackProvider.swift`

```swift
protocol HapticDevice: Sendable {
    func playSuccess()
}
protocol UserNotificationCenter: Sendable {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
}
protocol AppForegroundProbe: Sendable {
    @MainActor var isForeground: Bool { get }
}

@MainActor
final class CompletionFeedbackProvider {
    private let device: HapticDevice
    private let notifications: UserNotificationCenter
    private let foregroundProbe: AppForegroundProbe
    private var didRequestAuthorization = false

    func playSuccess()
    func ensureNotificationAuthorization() async
    func notifyTurnComplete(conversationTitle: String, preview: String) async
}
```

行为:
- `playSuccess()`:无条件 → `WKInterfaceDevice.current().play(.success)`(VM 在 success 路径直接调)。
- `notifyTurnComplete(...)`:仅当 `foregroundProbe.isForeground == false` 才 add notification。Content:title=`L10n.tr("AIChat")`,subtitle=`conversationTitle`,body=`preview` 截前 80 字符。trigger=`UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)`。
- `ensureNotificationAuthorization()`:首次调用 lazily request,`didRequestAuthorization` 之后短路。

集成:
- `AppEnvironment` 增加 `let completionFeedback: CompletionFeedbackProvider`。
- `AIChatApp` view appear 一次 `Task { await env.completionFeedback.ensureNotificationAuthorization() }`。
- VM `send` 成功路径:`feedback.playSuccess()` + `await feedback.notifyTurnComplete(...)`。

测试:`AIChat Watch AppTests/CompletionFeedbackProviderTests.swift`
- `test_playSuccessForwardsToHapticDevice`
- `test_notifyTurnComplete_skippedWhenForeground`
- `test_notifyTurnComplete_addsRequestWhenBackgrounded`
- `test_notifyTurnComplete_truncatesPreviewTo80Chars`
- `test_ensureAuthorization_onlyAsksOnce`
- `test_ensureAuthorization_swallowsErrorAndDeniedResult`

### 2.7 `ConversationDetailViewModel` 串接

修改:`AIChat Watch App/Stores/ConversationDetailViewModel.swift`

`init` 增加:`pacer: StreamingTextPacer`、`autoScroll: ConversationAutoScrollController`、`backgroundSession: BackgroundSessionCoordinator`、`feedback: CompletionFeedbackProvider`。

`send(text:attachments:)` 重写(替换 lines 67–94):
```swift
func send(text: String, attachments: [ChatAttachment]) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty || !attachments.isEmpty else { return }
    cancelStream()
    sendState = .sending
    lowBalanceVisible = false

    let snapshot = conversation
    streamTask = Task { [weak self] in
        guard let self else { return }
        self.backgroundSession.begin()
        defer { self.backgroundSession.end() }
        do {
            let upstream = self.chatService.send(userText: trimmed, attachments: attachments, to: snapshot)
            let paced = self.pacer.pace(upstream)
            self.sendState = .streaming
            for try await update in paced {
                if Task.isCancelled { break }
                self.conversation = update
                if let last = update.messages.last {
                    self.autoScroll.messageContentDidUpdate(latestMessageID: last.id)
                }
            }
            self.autoScroll.streamDidFinish()
            self.feedback.playSuccess()
            await self.feedback.notifyTurnComplete(
                conversationTitle: self.conversation.title,
                preview: self.conversation.messages.last?.cleanedText ?? ""
            )
            self.sendState = .idle
        } catch let error as RelayClientError {
            self.autoScroll.streamDidFinish()
            self.handle(relayError: error)
        } catch {
            self.autoScroll.streamDidFinish()
            self.sendState = .failed(error.localizedDescription)
        }
    }
}
```

`retryLast()` 行为不变。

### 2.8 `AppEnvironment` 注册

修改:`AIChat Watch App/AppEnvironment.swift`

新增字段:`streamingTextPacer`、`backgroundSession`、`completionFeedback`。

`init` 中:
- `self.streamingTextPacer = StreamingTextPacer()`
- `self.backgroundSession = BackgroundSessionCoordinator()`
- `self.completionFeedback = CompletionFeedbackProvider(...)`(默认实现)
- `chatService` 由直接构造改为 `RetryingChatService(inner: ChatService(...), policyProvider: ..., sleeper: ...)`(见 2.2)。

注:`ConversationAutoScrollController` 不进 AppEnvironment(per-screen 状态,view 自建)。

### 2.9 `ConversationDetailViewModelStreamingTests`(集成测试)

新增:`AIChat Watch AppTests/ConversationDetailViewModelStreamingTests.swift`

依赖:本阶段先在测试目标内放一个 minimal `MockChatService: ChatServiceProtocol`(完整 Mock streaming infra Phase 5 再做)。

测试用例:
- `test_send_beginsAndEndsBackgroundSession`
- `test_send_drivesAutoScrollOnEachUpdate`
- `test_send_playsHapticOnSuccess`
- `test_send_doesNotPlayHapticOnFailure`
- `test_send_skipsNotificationWhenForeground`
- `test_cancelStream_stopsBackgroundAndAutoScroll`

### 2.10 验证

```
xcodebuild -scheme "AIChat Watch App" \
  -destination "platform=watchOS Simulator,id=93A83695-2859-4388-B337-957616D03F55" \
  test
```

Phase 2 必须新增测试全绿:`RetryingChatServiceTests`、`StreamingTextPacerTests`、`ConversationAutoScrollControllerTests`、`BackgroundSessionCoordinatorTests`、`CompletionFeedbackProviderTests`、`ConversationDetailViewModelStreamingTests`。

手动验证(Phase 4 detail view 实装后做完整冒烟):
- 长回复字符级渐显,不再一次性甩到屏幕
- 流中向上滚 → 自动滚停止;新一轮 → 强制锚到底
- 息屏 5s 仍在续接 stream,完成时震动 + 通知(背景态)
- 模拟网络瞬断 → 自动重试 3 次后透明成功

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
- `AIChat Watch App/Persistence/ConversationPersistence.swift`、`AIChatSchemaV2.swift`(`AIChatMigrationPlanV1ToV2.swift` Phase 1 删除)
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
重点断言:Phase 1 `ActivationCenterViewModelRelayKeyStoreTests` 跑过 + 现有测试套不因删除迁移层退化;Phase 2 pacer / autoscroll / retry / background coordinator;Phase 3 同步 actor + StoreKit coordinator;Phase 4 各 VM 行为。

**UI 测试 + 截图**:
```
xcodebuild -scheme "AIChat Watch UITests" \
  -destination "platform=watchOS Simulator,id=93A83695-2859-4388-B337-957616D03F55" \
  test
```
Xcode Cloud 触发后,`ci_post_xcodebuild.sh` 拾取 `XCTAttachment` PNG,`ui-screenshots-bridge.yml` 派发 `ui-screenshots.yml` 把截图回贴到 PR。**每个 UI 影响改动必须在对应 UI 测试里调 `attachScreenshot`**(CLAUDE.md 已强制此约定)。

**手动实机验证**(Phase 1 / 2 / 3 各一次):
- Phase 1:全新装机 → 完成激活 → kill app → 再次启动应直接联通 relay(§11.1);确认删除迁移层后,首次启动可正常生成 V2 store。
- Phase 2:发长回复 → 字符级 reveal 平滑、auto-scroll 跟进、用户上滑应冻结自动滚;息屏 5s 应继续接收 stream,完成时震动 + 通知(§1 / §2)。
- Phase 3:两台同 Apple ID 设备会话 / pinned memory 互相同步;watchOS 受限时 iPhone 完成购买后 watch 余额刷新(§3 / §4)。
- Phase 4:语音录入、tools 开关、focus / memory / archive 编辑、AOD 隐私折叠均按预期工作。
- Phase 5:CI 上 Watch UI 测试套全绿,PR 评论里有完整截图集合。
