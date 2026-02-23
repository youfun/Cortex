---
name: jules-api
description: 调用 Google Jules API 进行远程代理协作编程。适用于跨仓库重构、自动 PR 生成、以及需要利用 Google 强大远程代理能力的场景。
---

# Jules API 协作技能

此技能允许 Gemini CLI 直接指挥远程 Jules 代理执行复杂的编程任务。

## <instructions>

### 触发场景
- 当用户要求在 GitHub 仓库中执行大规模代码变更时。
- 当需要自动创建 Pull Request 并进行自动化验证时。
- 当本地上下文不足以处理跨多个文件的复杂重构时。

### 核心工作流
1. **获取 Source**: 首先调用 `GET /v1alpha/sources` 确认仓库名。
2. **启动会话**: 使用 `POST /v1alpha/sessions` 发起任务。推荐开启 `AUTO_CREATE_PR`。
3. **监控进度**: 轮询 `GET /activities` 获取实时反馈。
4. **人工干预**: 如果发现计划不合理，使用 `sendMessage` 或 `approvePlan` 进行干预。

### 鉴权说明
- 必须通过环境变量 `JULES_API_KEY` 获取 API 密钥。
- 在 HTTP 请求头中添加 `X-Goog-Api-Key: $JULES_API_KEY`。

### 详细规范
关于 API 的具体参数和响应结构，请务必参阅 [api_docs.md](references/api_docs.md)。

## </instructions>

## 使用示例

### 1. 询问可用仓库
"激活 jules-api，帮我看看现在能对哪些仓库进行操作。"

### 2. 启动重构任务
"使用 jules-api 在 `sources/github/user/repo` 启动一个会话，任务是 '将所有 React 组件转换为 TypeScript'，并自动提交 PR。"

### 3. 查看进度
"查询会话 `sessions/12345` 的最新活动，看看进度如何了。"
