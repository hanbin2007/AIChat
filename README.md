# AIChat for Apple Watch

一个专门面向 Apple Watch 小屏场景设计的 Gemini 对话应用，支持：

- 多会话管理与新建对话
- 连续上下文对话
- 图片上传后联动 Gemini 多模态推理
- 本地持久化保存聊天记录
- 适配 watchOS 的卡片化聊天界面

## 项目结构

- `AIChat Watch App/Models`
  数据模型、图片附件归一化、会话标题生成
- `AIChat Watch App/Services`
  Gemini API client、本地仓库、运行时配置
- `AIChat Watch App/ViewModels`
  聊天状态管理与发送流程
- `AIChat Watch App/Views`
  Apple Watch 端会话列表、聊天详情、消息气泡和背景组件

## Gemini 配置

开发时二选一：

1. 在 Xcode Scheme 里注入环境变量 `GEMINI_API_KEY`
2. 在 target 的 `Info.plist` 里增加 `GEMINI_API_KEY`

可选环境变量：

- `GEMINI_MODEL`
  默认是 `gemini-2.0-flash`

## 本地构建

```bash
xcodebuild -scheme "AIChat Watch App" -destination "generic/platform=watchOS" build
```

## 生产建议

当前网络层已经被隔离在 `AIChat Watch App/Services/GeminiAPIClient.swift`，开发时可以直接连 Gemini。

如果要真正上线，建议把直连 API key 替换成你自己的后端中继或 token broker，避免把第三方密钥长期放在客户端。
