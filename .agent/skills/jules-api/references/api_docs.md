# Jules API 详细参考手册

Jules API 是连接 Google 远程 AI 编程代理的核心桥梁。

## 核心概念

- **代码源 (Sources)**: 代理的操作目标（例如 GitHub 存储库）。
- **工作会话 (Sessions)**: 一个独立的任务周期。
- **活动记录 (Activities)**: 会话中的每一步操作细节。

## API 接口详情

### 1. 获取代码源列表
`GET https://jules.googleapis.com/v1alpha/sources`
- 用于获取您已授权给 Jules 的仓库标识符（ID）。

### 2. 发起编程会话
`POST https://jules.googleapis.com/v1alpha/sessions`
- **请求体示例**:
  ```json
  {
    "prompt": "创建一个波霸奶茶展示应用！",
    "sourceContext": {
      "source": "sources/github/bobalover/boba", // 代码源 ID
      "githubRepoContext": {
        "startingBranch": "main" // 起始分支
      }
    },
    "automationMode": "AUTO_CREATE_PR", // 自动模式：自动创建 PR
    "title": "奶茶应用开发"
  }
  ```

### 3. 查询实时进度
`GET https://jules.googleapis.com/v1alpha/sessions/{会话ID}/activities`
- 建议通过轮询此接口来观察代理的思考过程、执行步骤及最终产出的 PR 链接。

### 4. 与代理对话
`POST https://jules.googleapis.com/v1alpha/sessions/{会话ID}:sendMessage`
- **请求体**: `{ "prompt": "请把背景改为粉色" }`

### 5. 确认执行计划
`POST https://jules.googleapis.com/v1alpha/sessions/{会话ID}:approvePlan`
- 仅在会话配置了 `requirePlanApproval: true` 时使用。

## 关键活动类型说明
- `planGenerated`: 代理已规划好步骤，等待执行或批准。
- `progressUpdated`: 代理正在运行 Shell 命令或修改文件，包含实时输出。
- `sessionCompleted`: 任务圆满完成！
