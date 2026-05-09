# Watch 客户端重写 —— 缺失功能清单

> **状态**:`claude/rewrite-apple-watch-client-CfNfP` 分支已落地"骨架重写",但功能等价度只到旧实现的 ~40%。本文件**完整列出**当前已知缺失项,作为后续补齐路线图。
>
> **不要把本文件当成正常的 deferred 列表**:其中**很多条是 PR 大重写时未声明就砍掉的**,需要明确补回,而不仅仅是"以后再做"。

---

## 分类说明

| 标签 | 含义 |
|---|---|
| 🔴 **未声明删除** | PR 把功能砍了但没在 commit message / 计划里说明,**用户会感知退化** |
| 🟡 **声明 deferred** | 大重写时已显式标注延后,目标是后续 PR 补 |
| 🟢 **骨架已建** | 新代码里有占位 / 协议,但没接线、没 UI、没人调用 |
| ⚪ **未验证** | 写了但没跑过,正确性未知 |

---

## 1. 流式渲染体验(🔴 未声明删除)

### 1.1 StreamingTextPacer
- **原文件**:`AIChat Watch App/ViewModels/StreamingTextPacer.swift` (~400 行)
- **作用**:relay 推一波 `answer_delta` 后,UI 不是一次性把全部新字符甩到屏幕上,而是在主线程上做**自适应字符级 reveal**(每 tick 一定字符数,根据队列深度动态调速),配 1Hz checkpoint 做 SwiftData 增量持久化
- **现状**:`ChatService.swift` 收到 `answerDelta` 直接 `assistant.text += delta` → 一次性全文 rebind → 视觉是"突然出现一大块字"
- **影响**:长回复的视觉体验明显退化;Apple Watch 屏幕小,这条 UX 是核心
- **测试覆盖**:旧有 `StreamingTextPacerTests.swift`,我也把它一起删了
- **怎么补**:把 pacer 拉回 `ChatService` 内部,把"网络层 delta" 和"UI 层渲染"解耦成两个 stream

### 1.2 ConversationAutoScrollController
- **原文件**:`AIChat Watch App/ViewModels/ConversationAutoScrollController.swift` (~350 行)
- **作用**:流式过程中自动 scroll-to-bottom,但**用户手动滚动一旦发生就停止自动滚**,直到本轮回复结束。还要识别"在同一气泡内 vs 跨气泡"的边界
- **现状**:`PlaceholderShell` 没滚动控制
- **影响**:长回复在小屏上几乎不可读
- **测试覆盖**:旧有 `ConversationAutoScrollControllerTests.swift`,删了
- **怎么补**:重写一个独立的 `ScrollAnchorController`,作为新 detail view 的依赖

### 1.3 ConversationHistoryRenderBudget(性能关键)
- **原文件**:`AIChat Watch App/Models/ChatModels.swift` 中 `ConversationHistoryRenderBudget` 枚举 + 围绕逻辑
- **作用**:决定什么消息要"折叠成预览"、什么消息要"完全渲染",阈值算法基于历史长度 + 当前消息位置 + render signature 缓存
- **现状**:`PlaceholderShell` 直接显示 `thread.messages.last?.text`,看不到滚动历史
- **影响**:重写历史消息列表时若直接全量渲染,会有严重的 hitch + 内存占用
- **测试覆盖**:`ConversationHistoryRenderBudgetTests.swift` 还在跑,**逻辑保留了但没消费方**
- **怎么补**:在新 `ConversationDetailView` 重渲染时直接用现有 `ConversationHistoryRenderBudget`

### 1.4 AssistantMessageContentNormalizer / RenderSignature 缓存
- **原文件**:`Models/ChatModels.swift` 第 1109+ 行
- **作用**:assistant 消息正文做规范化(去重 / 合并 thought 段 / 内嵌图像提取),并算出 render signature 防止 SwiftUI 不必要重渲染
- **现状**:逻辑还在文件里(没删),但新 view 没消费
- **影响**:同 1.3
- **怎么补**:新 detail view 直接用

---

## 2. 后台与可靠性(🔴 未声明删除)

### 2.1 后台 SSE 续传 + 系统通知
- **原行为**:用户在流式过程中息屏 / 退到后台,`ChatStore` 让 streaming 任务继续跑,完成时通过 `TranscriptionCompletionFeedbackProvider.notifyCompletion(...)` 发系统通知 + 震动唤醒
- **删除文件**:`Services/TranscriptionCompletionFeedbackProvider.swift`(~400 行)、`UITestBackgroundReplyDebugProbe`、`UITestBackgroundReplyCompletionFeedbackProvider`
- **现状**:`ChatService` 用 `Task.isCancelled` 检测取消,但**没有任何后台维持机制**;Watch 一旦熄屏 SwiftUI Task 会被系统暂停,流就断了
- **影响**:这是 Apple Watch 上长回复的核心体验
- **怎么补**:重新引入 `WKExtendedRuntimeSession`(原代码用了),配套写新的 `CompletionFeedbackProvider`

### 2.2 Send 重试逻辑
- **原行为**:`ChatStore.send(...)` 失败后根据 `SettingsService.sendFailureRetryLimit` 自动重试 N 次,带退避
- **现状**:`ChatService.send(...)` 失败一次就走 `.failed` 状态,要用户手动 retry
- **怎么补**:在 `ChatService` 包一层 retry 包装,读 `SettingsService.sendFailureRetryLimit`

### 2.3 Completion 触觉/声音反馈
- **原行为**:assistant reply 结束 / transcription 结束触发 `WKInterfaceDevice.current().play(.success)`
- **现状**:静默完成
- **怎么补**:同 2.1,在 `CompletionFeedbackProvider` 重写时一起恢复

---

## 3. 同步(🟡 声明 deferred)

### 3.1 iCloud(CloudKit)同步
- **删除文件**:`Services/ICloudConversationSyncService.swift`、`ConversationSyncCoordinator.swift`
- **作用**:多设备同 Apple ID 自动同步会话 + 全局 pinned + presets;支持 tombstone diff、冲突解决
- **现状**:Watch 完全独立,iPhone / 另一只 Watch 看不到同步
- **怎么补**:基于新 `ConversationPersistence` 重写一个 `iCloudSyncService`(actor);新 schema 友好 CloudKit

### 3.2 WatchConnectivity 配套设备同步
- **删除文件**:`Services/CompanionSyncBridge.swift`(~600 行)
- **作用**:跟 iPhone companion app 直接 push/pull 会话、附件 blob、relay pairing token、购买请求中转
- **现状**:**完全没有 companion 通信**
- **怎么补**:新写 `CompanionBridge` actor,API 围绕新 `ConversationPersistence`

---

## 4. StoreKit 购买流程(🟡 声明 deferred + 🟢 骨架)

### 4.1 watchOS 端 `Product.purchase()` 编排
- **现状**:`RelayPurchaseSheetViewModel.preparePurchase()` 拿到 `appAccountToken` 但**没人去调 StoreKit `Product.purchase(options:)`**
- **缺失文件**:`BillingPurchaseCoordinator`(原计划名)
- **怎么补**:写一个 `@MainActor` actor 持有 `Product` 缓存,把 prepare → purchase → submit 串起来

### 4.2 watchOS 受限时把购买请求转交给 iPhone
- **依赖**:3.2 的 CompanionBridge
- **现状**:**完全没有 fallback**

### 4.3 Restore 入口
- **现状**:`RelayPurchaseSheetViewModel.restorePurchases([])` 接受空数组,但没有"扫描已有 transactions"的本地逻辑

---

## 5. 附件管理(🔴 未声明删除)

### 5.1 Blob 外存生命周期
- **原 schema**:`ConversationAttachmentRecord.blobFilename` 字段 + `materializeAttachmentExports` 把附件 blob 写到 sidecar `attachments/` 目录,删除会话时 cascade 清理
- **新 schema**:`AttachmentEntity.data` 用 `@Attribute(.externalStorage)`,SwiftData 自动管
- **风险**:V1→V2 迁移时我**没有把 V1 的 sidecar blob 复制过来**,只读了 `attachment.data`。如果 V1 已经把 blob 移到 sidecar 文件并把 `data` 字段清空,迁移会丢内容
- **状态**:⚪ 未验证。**用户升级路径有数据丢失风险**
- **怎么补**:迁移时先 `materializeAttachmentExports` 把 V1 sidecar 加载回 `data` 字段,再写入 V2

### 5.2 附件预览 UI(图像 / 音频 / 文件)
- **原 Views**:`Views/Components/ChatBubbleView.swift` 等里有完整的 attachment 渲染
- **现状**:占位 shell 完全没有

---

## 6. Memory / Focus / Archive(🟢 骨架 + 🔴 未声明删除)

### 6.1 Memory maintenance 周期调度
- **原行为**:`ChatStore` 在每条 reply 完成后异步触发 `AIMemoryMaintenanceService.refreshArtifacts(...)`,把结果写回 conversation
- **现状**:`MemoryService` actor 存在,**但没有任何调用方**;新 `ChatService.send(...)` 完成后没有触发 memory refresh
- **怎么补**:`ChatService` 在 `done` 事件后异步调一次 `MemoryService`,merge 结果到 `ConversationThread` 再 upsert

### 6.2 Focus state / Pinned memory / Archive segment 的编辑 UI
- **原 Views**:`Views/ConversationSettingsView.swift` 有完整 UI
- **现状**:`ConversationSettingsViewModel` 只暴露 `setTitle` + `setAIConfiguration`,**focus/memory/archive 的 CRUD VM 接口完全没写**
- **怎么补**:扩展 `ConversationSettingsViewModel` 暴露 `setFocusState` / `addMemoryItem` / `removeMemoryItem` / `addPinnedMemory` 等

### 6.3 Global pinned memories CRUD UI
- **状态**:`ConversationPersistence.saveGlobalPinnedMemories(_:)` 已实现,但**没有 ViewModel 暴露 add/remove/edit**
- **怎么补**:写 `GlobalPinnedMemoryViewModel`

---

## 7. Tool 设置(🔴 未声明删除)

### 7.1 Google Search / Code Execution toggle UI
- **原文件**:`ViewModels/ConversationToolSettingsHelper.swift`(~250 行)
- **作用**:在会话 detail 页有一个工具菜单,可开关 Google Search 抓取 / Code Execution
- **现状**:`ConversationAIConfiguration.usesGoogleSearch` / `usesCodeExecution` 字段还在,`ChatService.buildStreamRequest` 也透传了,**但没 UI 让用户切换**
- **怎么补**:扩展 `ConversationSettingsViewModel`

---

## 8. 语音录入(🟢 骨架)

### 8.1 录音 UI + 转写流程
- **`Services/VoiceRecorder.swift`** 还在(没删),但**没人构造**
- **`TranscriptionService`** 已实现,但**没人调**(`ConversationDetailViewModel.transcribe(...)` 接口存在,UI 没接)
- **怎么补**:新 detail view 加录音按钮,VM 调 VoiceRecorder → TranscriptionService

### 8.2 录音状态机 / 倒计时 UI
- **原文件**:`ViewModels/VoiceRecordingHelper.swift`(~250 行,删了)
- **现状**:无

---

## 9. 列表 / 详情 / 设置 UI(🟡 声明 deferred,UI 重设计阶段)

### 9.1 ConversationListView
- **删除文件**:`Views/ConversationListView.swift`
- **占位**:`PlaceholderShell.ConversationsTab`,只有标题 + 简陋的 swipe delete + 一个 "New" 按钮
- **缺**:favorite filter、搜索、删除确认对话框、最近一条消息预览样式、未读标记

### 9.2 ConversationDetailView
- **占位**:**完全没有**(detail VM 存在,但 PlaceholderShell 不进 detail)
- **缺**:消息气泡、markdown 渲染、math 渲染、附件、流式光标、send 失败 retry、tool 菜单、语音输入按钮、低余额 Buy CTA

### 9.3 FavoritesView / PromptLibraryView / ConversationSettingsView / GlobalSettingsView / ActivationCenterView
- **占位**:每个 tab 一个最简 List 或 Form
- **缺**:几乎全部具体 UX

### 9.4 RelayStatusDot / 配置横幅 / 激活状态卡片
- **删除文件**:`Views/Components/RelayStatusDot.swift`、`ConfigurationBannerView.swift`、`ActivationStatusCard.swift`
- **现状**:无

### 9.5 设计系统
- **删除文件**:`Views/Components/DesignSystem.swift`
- **作用**:统一颜色 / 间距 / 字号
- **现状**:无,新 placeholder 用 SwiftUI 默认

### 9.6 Markdown / Math 渲染消费
- **保留 package**:`Packages/MarkdownView`、`Packages/swiftui-math`
- **删除消费方**:`Views/Components/AssistantMessageMarkdownView.swift`
- **现状**:package 还在,**没人用**

---

## 10. UI 测试矩阵(🟡 声明 deferred,UI 重设计阶段)

旧 UI 测试 ~7 个 scenario(formula_zoom, tool_entry, conversation_navigation, conversation_delete_persistence, auto_scroll_interrupt, touch_scroll, list_scroll_performance, heavy_markdown, reply_completion_anchor, background_reply_notification, latest_message_expanded, latest_thought_summary_collapsed, streaming_scroll_performance, streaming_stress)全删了,只剩 `LaunchSmokeTests.swift` 的最小冒烟。

UI 重设计阶段必须重新设计这套测试矩阵,**不要直接移植**:旧 scenarios 紧耦合 ChatStore + UITestBootstrap。

---

## 11. Activation 流程(🔴 未声明删除 + ⚪ 未验证)

### 11.1 Activation 完成后写回 RelayKeyStore
- **现状**:`ActivationCenterViewModel.bootstrap()` 把 status 拿回来更新 VM 内部 `currentBearerKey`,**但没有写到 `RelayKeyStore`(UserDefaults)**
- **影响**:下次启动 `AppConfiguration.resolvedRelayBearerToken` 读不到 key,只能再次 bootstrap;实际部署可能直接卡死(若服务端拒绝重复 bootstrap)
- **修复**:5 行代码,在 ActivationCenterViewModel 收到 status 后调一次 `RelayKeyStore.set(status.key?.keyValue, appGroupIdentifier: ...)`
- **优先级**:**🚨 最高,这条不修生产装机就跑不通**

### 11.2 Pairing token 在 iPhone companion 端的接收链路
- **依赖**:3.2 CompanionBridge
- **状态**:`RelayPairingTokenViewModel` 能拿 token 显示,但 iPhone 端无法收到
- **影响**:跨设备配对走不通

### 11.3 Offline activation 流程
- **`OfflineActivation`** 还在 `Activation/`(没删),`ActivationCenterViewModel.redeemOffline(...)` 暴露了接口
- **缺**:实际**没有 UI 输入激活码 / 显示 fingerprint**;也没有"在 iPhone companion 上输入,push 到 watch"的链路

---

## 12. 持久化与迁移(⚪ 未验证)

### 12.1 V1→V2 迁移测试
- **原计划要写**:`MigrationV1ToV2Tests.swift` 用 V1 fixture sqlite 跑迁移,断言所有数据存在 + 重跑幂等
- **现状**:**没写**
- **优先级**:**🚨 高**,真实用户升级数据安全无验证

### 12.2 V2 schema 缺字段
- 我对照 V1 schema:V2 missing 的字段已加回 `focusStateData`。**其他字段已对齐**
- 但 V2 没有 V1 的 `ConversationStoreMetadataRecord.legacyImportCompletedAt` 等价 —— 用 `StoreMetadataEntity.migratedFromV1At` 替代,语义对应

### 12.3 SwiftData CloudKit 集成(可选)
- 旧的没启用 CloudKit,新的也是 `cloudKitDatabase: .none`,一致

---

## 13. SettingsService(🟢 骨架,没全部对接)

### 13.1 transcription 设置 UI
- 字段已在 `SettingsService` + `GlobalSettingsViewModel` 暴露
- **占位 shell 没有 Form 控件**

### 13.2 Send retry 上限滑块
- 同上

### 13.3 Auto-scroll 开关 UI
- 同上

---

## 14. AOD 隐私 / 锁屏行为(🔴 未声明删除)

- **删除测试**:`AODPrivacyTests.swift`
- **保留服务**:`Services/WatchDisplayStateMonitor.swift`(感知是否 luminance reduced)
- **删除使用方**:`AIChatApp.swift` 里的 `WatchDisplayStateObserver` 视图
- **影响**:AOD(熄屏常显)状态下旧版会隐藏敏感对话内容;新版**没有这个保护**
- **怎么补**:在新 detail view 加 `@Environment(\.isLuminanceReduced)` 观察 + WatchDisplayStateMonitor 调用

---

## 15. UI Test bootstrap(🟡 声明 deferred,UI 重设计阶段)

`UITestBootstrap` + 一堆 scenario 的 mock streaming services 全部删除。新的 UI 重设计阶段需要:
- 一套基于新 ChatService 的 mock(`MockChatService` 协议化)
- AIChat_UI_TEST_SCENARIO 环境变量重新支持
- ASC 截图桥接路径保持不变(`ci_post_xcodebuild.sh` + `ui-screenshots-bridge.yml`)

---

## 优先级总览

### 🚨 上线前必须补(否则装机不可用)
1. **§11.1** ActivationCenterViewModel → RelayKeyStore 写回(5 行)
2. **§12.1** V1→V2 迁移测试 + 一套真 V1 fixture(否则升级用户数据丢失)
3. **§5.1** V1→V2 迁移把附件 sidecar blob 还原进 `data`(否则附件丢)

### 🔴 用户立刻感知的退化(必须在第一个真 UI release 之前补)
4. **§1.1** StreamingTextPacer
5. **§1.2** ConversationAutoScrollController
6. **§2.1** 后台续传 + 完成通知
7. **§2.3** Completion haptic
8. **§2.2** Send 重试

### 🟡 跨设备 / 计费走通才能 GA
9. **§3.1** iCloud sync 重写
10. **§3.2** CompanionBridge 重写
11. **§4.1** BillingPurchaseCoordinator
12. **§4.2** iPhone 购买 fallback

### 🟢 UI 重设计阶段一并补
13. §6 / §7 / §8 / §9 / §10 / §13 / §14 / §15 全部 —— 当 UI 重设计立项后,这些都是 view 层 + 配套 VM 接口扩展

---

## 措辞更正

之前 commit message 与 PR 描述里写的"完全重写"、"完全功能等价"措辞**不准确**。客观描述应是:

> 后端 + 持久化 + ViewModel 骨架已重写为 relay-only / 严格 MVVM。功能等价度约 40%:
> - **保留**:Networking 全集、Persistence(含 V1→V2 迁移逻辑)、StreamChat、Transcribe、MemoryExtract、Activation、Billing prepare/submit/restore、Pairing
> - **砍掉等待补回**:streaming pacer、auto-scroll、后台续传、completion 反馈、send 重试、attachment sidecar 迁移、tool 设置 UI、AOD 隐私
> - **声明 deferred**:iCloud + WatchConnectivity 同步、StoreKit 编排、整套 UI 重设计、UI 测试矩阵

下次提 PR 描述时按上述措辞写。
