# 调试 Phoenix 应用

- 优先使用 `iex -S mix phx.server` 进行交互式调试，它提供运行中的应用以及连接的 observer。
- 若需要调查某条失败的测试，运行 `mix test --trace <file>` 可以获取详细的失败上下文与堆栈。

## 推荐步骤
1. 启动 `iex -S mix phx.server` 并手动复现请求或信号流；必要时临时加 `Logger.debug/1` 以提高可见性。
2. 在运行的 shell 中使用 `:observer.start()`（允许时）或 `:dbg` 跟踪 `SignalHub` 等进程之间的消息。
3. 若需底层 OTP 调试，可以将 `:debugger` 挂到处理信号的 GenServer，而不是遍地插入 IO；保持这类监控短暂存在。
4. 添加的临时日志用于调试后务必移除，以保持信号流简洁。

## 与信号相关的提示
- 调试时避免引发信号级联；只发送正在验证的通知。
- 重放失败流程时必须保持 origin 元数据一致（`provider`、`event`、`action`、`actor`、`origin`），确保下游服务看到相同负载。
