# Relay Gateway

现在仓库里有两种 relay 方案：

- 推荐：`AIChat Relay` macOS 原生 app，带 UI、日志和一键启动
- 备用：当前目录下的 Node 示例服务

如果你就是要在 mac 上开箱即用地跑服务端，优先直接打开 Xcode 的 `AIChat Relay` scheme。

## macOS App

```bash
xcodebuild -project AIChat.xcodeproj -scheme "AIChat Relay" -destination "platform=macOS" build
```

桌面 app 会负责：

- 保存 `GEMINI_API_KEY`
- 生成和保存 `RELAY_BEARER_TOKEN`
- 启动本地 HTTP relay
- 显示 `localhost` / 局域网地址
- 提供客户端可直接复制的 `xcconfig` 配置片段

## Node Fallback

这是给 Apple Watch 客户端准备的最小中继服务。作用：

- 在服务端持有 `GEMINI_API_KEY`
- 对客户端做 Bearer 鉴权
- 把 Gemini 的 SSE 流转换成 `answer_delta` / `thought_delta` 事件流

## 启动

```bash
export GEMINI_API_KEY=your-gemini-key
export RELAY_BEARER_TOKEN=your-relay-token
node relay/server.mjs
```

## 客户端配置

在 `Config/Secrets.xcconfig` 里填：

```xcconfig
AI_BACKEND_MODE = relay
AI_RELAY_BASE_URL = http:/$()/127.0.0.1:8787
AI_RELAY_BEARER_TOKEN = your-relay-token
GEMINI_MODEL = gemini-3-flash-preview
```

注意：`.xcconfig` 里的 `//` 会被当成注释，所以这里不能直接写 `http://...`。
