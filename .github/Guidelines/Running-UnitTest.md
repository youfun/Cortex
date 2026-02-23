# 运行单元测试

- 使用 `mix test` 运行测试，覆盖你修改相关的 Elixir 与 Phoenix 套件。
- 当测试依赖外部 API 或在线数据库时，使用 `LIVE=true mix test`，并说明为什么必须加 `LIVE=true`。

## 工作流程
1. 提交代码改动后运行 `mix test`，确保没有回退问题。
2. 若只需运行部分测试，可指定测试文件，例如 `mix test test/some_feature_test.exs`。
3. 需要更详细的失败信息时，使用 `mix test --trace`，它会打印每个用例的开始/结束与失败详情。

## 分析失败
- 终端中 `mix test` 的输出是判定通过/失败的唯一信号；在下结论前务必完整阅读。
- 若测试卡住，可临时加入日志或使用 `mix test --max-failures 1` 先定位失败位置。
- 发射信号的测试要断言外部副作用（数据库写入、消息发送）而非进程内部状态。
