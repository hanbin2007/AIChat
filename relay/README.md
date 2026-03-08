# Relay Gateway

这是给 Apple Watch 客户端准备的最小中继服务。作用：

- 在服务端持有 `GEMINI_API_KEY`
- 对客户端做 Bearer 鉴权
- 把 Gemini 的 SSE 流转换成更简单的 `delta` 事件流

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
AI_RELAY_BASE_URL = http://127.0.0.1:8787
AI_RELAY_BEARER_TOKEN = your-relay-token
GEMINI_MODEL = gemini-2.5-flash
```
