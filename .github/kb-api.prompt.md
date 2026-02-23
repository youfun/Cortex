# 更新知识库（Phoenix/Elixir：API 说明）

- 只看“最新一条聊天消息”（LATEST chat message），忽略所有历史对话；最新消息包含你要对知识库做的事情。
- 目标：按请求更新知识库内容（面向 Phoenix + Elixir 项目）。

## 实施知识库更新

- 先理解知识库组织方式与入口文件：
  - 首选：`REPO-ROOT/.github/copilot-instructions.md`（如果存在）
  - 知识库入口通常是：`REPO-ROOT/.github/KnowledgeBase/Index.md`
  - 如果仓库结构不同：在仓库内搜索 `KnowledgeBase/Index.md` 或知识库入口 `Index.md`，并以实际存在的入口为准。

- 请求可能包含多个目标（objectives）。对每个目标：
  - 确认它属于哪个项目/子系统（Phoenix Web、Context/Domain、数据层、OTP 服务、外部集成等）。
  - 浏览该项目下的所有分类，找到最合适的分类：
    - 若没有明显合适的分类：新增一个分类。新增分类需要配套新增一个 guideline 文件，并把它加入知识库工程结构里。
    - 新分类通常加在该项目的末尾，避免打乱既有结构。
  - 若分类描述需要补充（例如补充模块边界、主要入口点），则更新描述。
  - 打开分类条目链接的目标文件，按请求更新内容。

## 新增/更新 `API Explanation` 指南的写作要求（Phoenix/Elixir）

- 内容必须紧凑：不要重复“读源码就能直接看懂”的内容；重点写“如何正确使用/如何串起来/有哪些坑”。
- 写清楚 API 的“归属层级”与“调用入口”：
  - Web API：Controller/LiveView/Components 的对外接口（事件名、参数形状、返回/assign 变化）。
  - 业务 API：Context 模块的 `module.function/arity`（例如 `create_*`、`update_*`、`list_*`、`get_*`）、输入/输出结构、错误形态（`{:ok, ...}` / `{:error, changeset}` / `:error` 等）。
  - 数据 API：schema changeset、query 组合、事务边界（`Repo.transaction/1`、`Ecto.Multi`）的约束与惯例。
  - 外部集成：HTTP 使用 `Req` 的封装入口、重试/超时/认证策略的放置位置。

- 不要为了“展示”而放代码样例：
  - 如果必须给样例：只写 API 的最小调用顺序（避免粘贴内部实现），并尽量使用真实的 `module.function/arity` 名称。
  - 不要用代码样例替代解释（比如最佳实践/常见用途/注意事项应以文字说明）。
  - 代码样例只有在“必须按特定顺序组合多个函数/模块”时才有价值（例如测试文件结构、或多步骤 workflow）。
