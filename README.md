# AIChat for Apple Watch

一个面向 Apple Watch 小屏交互构建的 AI 对话应用，当前已经具备：

- 多会话列表、新建、删除、重命名、清空
- 上下文续聊与本地持久化
- 图片上传并参与 Gemini 多模态推理
- 流式回复显示，而不是整段返回
- Gemini thinking 摘要展示与会话级思考强度切换
- 会话内快速模型切换，支持 `Gemini 3 Flash` / `Gemini 3.1 Pro`
- 可切换 `Direct Gemini` 和 `Relay Gateway`
- 新增 `AIChat Relay` macOS 原生桌面服务端，带 UI、日志、LAN 地址展示和一键启动
- 为未来 iPhone 伴生端准备的共享存储与 `WatchConnectivity` 同步桥

## 目录

- `AIChat Watch App/Models`
  会话、消息、图片附件和标题生成
- `AIChat Watch App/Services`
  Gemini client、relay client、配置、存储、同步桥
- `AIChat Watch App/ViewModels`
  聊天状态与流式发送流程
- `AIChat Watch App/Views`
  Apple Watch UI、聊天页、设置页、消息气泡
- `Config`
  Xcode 构建配置与本地 secrets
- `relay`
  一个最小可运行的 Node relay 示例
- `AIChat Relay`
  macOS 原生 relay app，推荐本地开发和自托管时直接使用

## 本地配置

1. 复制 `Config/Secrets.xcconfig.example` 为 `Config/Secrets.xcconfig`
2. 选择一种模式

开发直连 Gemini：

```xcconfig
AI_BACKEND_MODE = direct
GEMINI_API_KEY = your-gemini-api-key
GEMINI_MODEL = gemini-3-flash-preview
```

生产推荐 relay：

```xcconfig
AI_BACKEND_MODE = relay
AI_RELAY_BASE_URL = http://127.0.0.1:8787
AI_RELAY_BEARER_TOKEN = your-relay-token
GEMINI_MODEL = gemini-3-flash-preview
```

可选共享容器：

```xcconfig
APP_GROUP_IDENTIFIER = group.your.company.aichat
```

说明：

- `Config/Secrets.xcconfig` 已经被 `.gitignore` 忽略
- 直连 Gemini 只适合开发，不适合真正上线
- 如果要让 iPhone 和 Watch 真正共享文件存储，需要再给 target 配好 App Group entitlement
- `Gemini 3` 会走 `thinkingLevel`，`Gemini 2.5` 会自动映射到 `thinkingBudget`

## 构建

```bash
xcodebuild -scheme "AIChat Watch App" -destination "generic/platform=watchOS" build
```

测试代码编译：

```bash
xcodebuild -scheme "AIChat Watch App" -destination "generic/platform=watchOS Simulator" build-for-testing
```

构建 macOS relay：

```bash
xcodebuild -project AIChat.xcodeproj -scheme "AIChat Relay" -destination "platform=macOS" build
```

## Relay

优先使用新的 `AIChat Relay` macOS app。

它提供：

- 原生 SwiftUI 桌面 UI，不依赖单独安装 Node
- 内置本地 HTTP 服务，直接兼容客户端当前的 `/v1/chat/stream` 协议
- Bearer 鉴权、Gemini SSE 转发、请求日志、LAN / localhost 地址展示
- 可直接复制 `Config/Secrets.xcconfig` 片段，把 Watch / iPhone 客户端切到 relay

Node 中继示例仍保留在 `relay/server.mjs` 和 `relay/README.md`，适合作为无 UI 的备用方案。

它做三件事：

- 服务端持有 `GEMINI_API_KEY`
- 对客户端做 Bearer 鉴权
- 把 Gemini SSE 流转成客户端更容易消费的 `answer_delta` / `thought_delta` 事件

## 当前状态

工程已经可以成功构建，并且 watch app 可以直接安装到 watchOS 模拟器启动。

如果你现在还没填 `Config/Secrets.xcconfig`，应用会正常启动，但会显示 Gemini 配置提示卡片，而不会真正发请求。
