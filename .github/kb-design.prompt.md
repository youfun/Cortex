# 更新知识库（Phoenix/Elixir：设计说明）

## 目标与约束

- 目标：在 `Copilot_KB.md` 里起草知识库文档（面向 Phoenix + Elixir 项目）。
- 仅允许更新 `Copilot_KB.md` 与知识库目录下的文档；不要修改其它文件。
- 任何源码引用必须用 `单行 code` 或 ```多行 code``` 包起来（仅用于“指向/引用”，不要粘贴大段源码）。
- 先阅读并理解仓库的 Copilot 指南与知识库入口文件：
  - 首选：`REPO-ROOT/.github/copilot-instructions.md`
  - 知识库入口通常是：`REPO-ROOT/.github/KnowledgeBase/Index.md`
  - 如果仓库结构不同：在仓库内搜索 `KnowledgeBase/Index.md` 或 `Index.md`（知识库入口），并以实际存在的入口文件为准。
  - 下文出现的 `Index.md` 默认指知识库入口文件。

## 识别问题类型

- 目标：围绕我给你的主题，为知识库起草一份“设计说明/实现细节”文档。
- 只看“最新一条聊天消息”（LATEST chat message），忽略所有历史对话里的 `# Topic/# Ask/# Draft/# Improve/# Execute`。

- 若最新消息里有 `# Topic`：表示新开题。
  - 用仅一个标题 `# !!!KNOWLEDGE BASE!!!` 覆盖 `Copilot_KB.md` 的全部内容。
  - 在 `Copilot_KB.md` 新增 `# DOCUMENT REQUEST`，并将 `# Topic` 的“问题描述”原样复制到 `## TOPIC` 下的 `## TOPIC` 小节中。
  - 然后按 “Steps for Topic” 完成该小节中的 `### Insight`。

- 若最新消息里有 `# Ask`：表示需要澄清/更深入。
  - 将 `# Ask` 的“问题描述”原样复制到 `# DOCUMENT REQUEST` 下新增的 `## ASK`。
  - 然后按 “Steps for Ask” 完成 `## ASK` 的 `### Insight`，并在必要时修正 `## TOPIC`（尽量只改 `## TOPIC`，保持范围最小）。

- 若最新消息里有 `# Draft`：表示可以开始写草稿。
  - 将 `# Draft` 的“问题描述”原样复制到 `# DOCUMENT REQUEST` 下新增的 `## DRAFT`。
  - 然后按 “Steps for Draft” 在 `Copilot_KB.md` 末尾追加草稿。

- 若最新消息里有 `# Improve`：表示优化草稿。
  - 将 `# Improve` 的“问题描述”原样复制到 `# DOCUMENT REQUEST` 下新增的 `## IMPROVE`。
  - 然后按 “Steps for Improve” 更新草稿的 `# DRAFT-*` 区块。

- 若最新消息里有 `# Execute`：表示落库。
  - 按 “Steps for Execute” 将草稿内容落到知识库文件结构中（保持 `Copilot_KB.md` 不变）。

- 若最新消息里什么都没有：说明你意外中断了。
  - 通读 `Copilot_KB.md`，继续处理 `# DOCUMENT REQUEST` 的最后一个未完成请求。

- 规则：`# DOCUMENT REQUEST` 里已有内容一律冻结；只有在澄清阶段确认分析错误时才允许修改，且尽量限制在 `## TOPIC`。

## Steps for Topic（Phoenix/Elixir 设计分析）

- 目标：完成 `# DOCUMENT REQUEST` → `## TOPIC` → `### Insight`。
- `# Topic` 给出的主题通常对应 Phoenix/Elixir 项目的一个“功能点”，会跨越多个组件与层（Web 层、上下文、数据层、OTP 等）。

- 必须从源码里找清楚并写出来（每一点都要能在源码中指到具体“模块/函数/职责”）：
  - **入口点（entry point）**
    - Phoenix Web：通常从 `lib/*_web/router.ex` 的路由开始，落到某个 Controller action 或 LiveView。
    - LiveView：说明对应 LiveView 的 `mount/3`、`handle_params/3`、`handle_event/3`、`handle_info/2` 的职责分工与调用顺序。
    - Plug：若功能涉及 pipeline / plug chain，说明 plug 的顺序、主要分支与中间 assign。
  - **核心逻辑（core part）**
    - Context：通常在 `lib/*/` 的 context 模块中（例如 `create_*`、`update_*`、`list_*`、`get_*` 等），说明它们如何组合 schema、query、changeset、事务。
    - 数据层：Ecto schema + changeset + query（`Ecto.Query`）+ `Repo`（含 `Ecto.Multi`/事务边界）如何协作。
    - 外部依赖：若涉及 HTTP，优先说明 `Req` 的封装位置与调用路径（而不是散落在 Web 层）。
  - **分支/场景（cases）**
    - 识别所有分支来源：函数多子句（pattern matching）、`case/cond/with`、配置（`config/*.exs`）、Feature flag、权限与认证分支等。
    - 尽量枚举齐全：成功/失败、校验错误、未授权、资源不存在、异步/超时等。
  - **递归/循环结构（recursion / iterative structure）**
    - Elixir 常见的是“递归函数 + 模式匹配”或 `Enum.reduce/3` 等；如果存在，说明递归终止条件与状态演进。
    - 若是 OTP（GenServer/Task/Supervisor）循环（如 `handle_info/2` 触发下一轮），说明消息来源与周期。

- 需要解释的设计维度（都要贴近 Phoenix/Elixir 项目组织方式）：
  - 架构：`*_web`（Web 层）与 context（业务层）与 schema/repo（数据层）的边界在哪里。
  - 组件组织：LiveView/Controller/Context/Schema/Changeset/Query/Repo/OTP 之间的依赖方向与调用关系。
  - 执行流：从 HTTP 请求或 LiveView 事件开始，到最终的 DB 写入/读取与页面/流更新结束的完整链路。
  - 设计模式：Phoenix “Contexts”、Plug pipeline、LiveView 状态机（socket assigns）、OTP supervision 等（若实际代码使用）。

- 内容要求（保持紧凑但可定位）：
  - 引用源码时不要贴代码片段；用 `模块名.函数/arity` + 该函数内部的关键段落来定位。
  - 不要使用行号（源码会变动）。
  - 文档用于未来改代码时快速定位修改点：尽量写“名字”和“路径”（模块/函数/职责），避免过度抽象。

## Steps for Ask

- 目标：完成 `# DOCUMENT REQUEST` → `## ASK` → `### Insight`。
- `# Ask` 里是需要澄清的结论/疑点：
  - 逐条回答问题，补足你需要更深入挖掘的 Phoenix/Elixir 细节（比如具体路由到哪个 LiveView/Controller，具体调用哪个 context 函数）。
  - 如果确认之前的 `## TOPIC` 有错误或遗漏：修正它，但尽量只改 `## TOPIC`，保持变更范围小。

## Steps for Draft

- 目标：在 `Copilot_KB.md` 末尾追加一份“知识库草稿文档”。
- `# DOCUMENT REQUEST` 必须保持不变；你需要仔细阅读它并将其中所有要点重新组织成一篇可读的知识库文档。
- 最新消息 `# Draft` 可能包含额外信息，必须一并使用。
- 必须新增以下区块：
  - `# DRAFT-LOCATION`：说明将来要把这篇文档放到知识库 `Index.md` 的哪个项目、哪个分类（通常是该项目的 `Design Explanation` 下新增主题）。此阶段只改 `Copilot_KB.md`，不要改 `Index.md`。
  - `# DRAFT-TITLE`：简短但覆盖面足够的标题。
  - `# DRAFT-CONTENT`：草稿正文。
- 草稿质量要求：
  - 100% 基于项目源码与 `# DOCUMENT REQUEST` 的所有结论；一个点都不能漏。
  - 不要只是“总结”；`# DOCUMENT REQUEST` 已经很像总结，你要把它整理成结构化文档。
  - 允许多级 Markdown 标题；鼓励用条目列出模块/函数/流程与分支。

## Steps for Improve

- 目标：根据最新消息 `# Improve` 的建议更新草稿的 `# DRAFT-*` 区块。

## Steps for Execute

- 按 `# DRAFT-LOCATION`：在知识库 `Index.md` 的对应项目里，在 `Design Explanation` 下新增主题条目。
  - 用 bullet points 写主题描述，覆盖最关键的定位点，便于未来检索。
- 按 `Index.md` 的链接创建/更新目标文件，并将 `# DRAFT-CONTENT` 的内容“原样”写入（不包含 `# DRAFT-CONTENT` 这个标题）。
- 保持 `Copilot_KB.md` 不变。
