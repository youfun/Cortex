# Sprint 1 Token 优化 - Code Skimming 场景
# Feature: Code Structure Extraction (Code Skimming)

[SCENARIO: SKIM-001] TITLE: Extract Elixir module structure with AST parsing TAGS: integration skim token
GIVEN 一个包含多个函数和复杂实现的 Elixir 文件
WHEN 调用 read_file_structure 工具
THEN 返回内容包含模块名
THEN 返回内容包含函数签名 (def/defp/defmacro)
THEN 返回内容包含 @spec 和 @type 定义
THEN 返回内容包含 use/import/alias 指令
THEN 返回内容不包含具体的函数体业务逻辑代码
THEN Token 消耗应小于原文件的 20%

[SCENARIO: SKIM-002] TITLE: Fallback to regex when Elixir file has syntax errors TAGS: integration skim token
GIVEN 一个包含语法错误的 Elixir 文件
WHEN 调用 read_file_structure 工具
THEN 返回内容包含 "Regex Fallback" 标识
THEN 返回内容仍能提取 defmodule 和 def 声明
THEN 工具不应返回错误

[SCENARIO: SKIM-003] TITLE: Extract Python structure with classes and functions TAGS: integration skim token
GIVEN 一个包含 class 和 def 的 Python 文件
WHEN 调用 read_file_structure 工具
THEN 返回内容包含 class 名称
THEN 返回内容包含 def 函数签名
THEN 返回内容不包含函数体实现
THEN Token 消耗应显著降低

[SCENARIO: SKIM-004] TITLE: Extract Golang structure with types and functions TAGS: integration skim token
GIVEN 一个包含 struct 和 func 的 Golang 文件
WHEN 调用 read_file_structure 工具
THEN 返回内容包含 type 声明
THEN 返回内容包含 func 函数签名
THEN 返回内容不包含函数体实现
THEN Token 消耗应显著降低

[SCENARIO: SKIM-005] TITLE: Extract JavaScript/TypeScript structure TAGS: integration skim token
GIVEN 一个包含 class 和 function 的 TypeScript 文件
WHEN 调用 read_file_structure 工具
THEN 返回内容包含 class 和 function 签名
THEN 返回内容不包含函数体实现
THEN Token 消耗应显著降低

[SCENARIO: SKIM-006] TITLE: Extract Rust structure TAGS: integration skim token
GIVEN 一个包含 struct 和 impl 的 Rust 文件
WHEN 调用 read_file_structure 工具
THEN 返回内容包含 struct 声明
THEN 返回内容包含 impl block 的函数签名
THEN 返回内容不包含函数体实现
THEN Token 消耗应显著降低

[SCENARIO: SKIM-007] TITLE: Handle unsupported file types with preview TAGS: unit skim token
GIVEN 一个未知类型的文件
WHEN 调用 read_file_structure 工具
THEN 返回内容应包含 preview
THEN 返回内容应标识 "Unsupported file type"

[SCENARIO: SKIM-008] TITLE: Handle empty files gracefully TAGS: unit skim token
GIVEN 一个空文件
WHEN 调用 read_file_structure 工具
THEN 返回内容应为 "Empty file"
THEN 工具不应返回错误

[SCENARIO: SKIM-009] TITLE: Validate file path security TAGS: unit skim security
GIVEN 一个包含 .. 的路径
WHEN 调用 read_file_structure 工具
THEN 工具应拒绝该路径
THEN 返回错误 "path traversal detected"

[SCENARIO: SKIM-010] TITLE: Handle non-existent files TAGS: unit skim token
GIVEN 一个不存在的文件路径
WHEN 调用 read_file_structure 工具
THEN 工具应返回 "file not found" 错误
