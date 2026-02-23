defmodule Cortex.SignalHub do
  @moduledoc """
  Cortex 的信号总线中枢。

  所有组件之间严禁直接调用，必须通过本模块发射和订阅信号。

  ## 信号类型约定

  - `user.input.*`       - 用户输入事件
  - `tool.call.*`        - 工具调用请求
  - `tool.result.*`      - 工具执行结果
  - `shell.output.*`     - Shell 命令输出流
  - `file.changed.*`     - 文件变更通知
  - `agent.think`        - Agent 思考过程
  - `agent.response`     - Agent 最终响应
  - `skill.loaded`       - 技能加载成功
  - `skill.error`        - 技能加载失败
  - `system.error`       - 系统错误
  - `system.heartbeat`   - 心跳信号
  - `session.branch.*`   - 会话分支操作
  """

  require Logger

  alias DateTime
  alias Jido.Signal.TraceContext

  @bus_name :cortex_bus
  @default_source "/studio"
  @default_specversion "1.0.2"

  @doc """
  返回信号总线的注册名称，供 Application 启动树使用。
  """
  def bus_name, do: @bus_name

  @doc """
  返回 Bus 的 child_spec，用于放入 Supervisor 启动树。
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {Jido.Signal.Bus, :start_link, [[name: @bus_name] ++ opts]},
      type: :supervisor
    }
  end

  @doc """
  发射信号到总线。

  ## 参数
  - `type`   - 信号类型，如 "tool.call.read"
  - `data`   - 数据载荷 map
  - `opts`   - 可选参数
    - `:source` - 信号来源（默认 "/studio"）

  ## 示例

      Cortex.SignalHub.emit("tool.call.read", %{
        provider: "agent",
        event: "tool",
        action: "call",
        actor: "coder",
        origin: %{channel: "agent", client: "coder", platform: "server"},
        path: "/src/app.ex"
      }, source: "/agent/coder")
  """
  def emit(type, data, opts \\ []) do
    source = Keyword.get(opts, :source, @default_source)
    specversion = Keyword.get(opts, :specversion, @default_specversion)
    time = Keyword.get_lazy(opts, :time, &DateTime.utc_now/0)
    causation_id = Keyword.get(opts, :causation_id)

    case normalize_data(data) do
      {:ok, normalized_data} ->
        case Jido.Signal.new(type, normalized_data,
               source: source,
               specversion: specversion,
               time: time
             ) do
          {:ok, signal} ->
            # 自动注入追踪上下文
            traced_signal = maybe_propagate_trace(signal, causation_id)

            # 发射信号到总线。依靠应用启动树确保 @bus_name 进程可用。
            Jido.Signal.Bus.publish(@bus_name, [traced_signal])
            {:ok, traced_signal}

          {:error, reason} ->
            Logger.error("[SignalHub] Failed to create signal: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, {:missing_fields, missing}} ->
        Logger.warning(
          "[SignalHub] Rejected non-compliant signal emit. type=#{type} missing_fields=#{inspect(missing)} data=#{inspect(data)}\n" <>
            "Standard requires: provider, event, action, actor, origin."
        )

        {:error, {:missing_fields, missing}}
    end
  end

  @required_fields [:origin, :provider, :event, :action, :actor]
  @fixed_fields Enum.reverse([:payload | Enum.reverse(@required_fields)])

  defp normalize_data(data) when is_list(data), do: normalize_data(Map.new(data))

  defp normalize_data(data) when is_map(data) do
    missing_fields = Enum.filter(@required_fields, &(!Map.has_key?(data, &1)))

    if missing_fields == [] do
      # 如果已经包含必需字段，尝试合并/提取 payload
      payload = Map.get(data, :payload, %{})
      other_fields = Map.drop(data, @fixed_fields)

      # 如果除了固定字段外还有其他字段，则合并到 payload
      merged_payload =
        if map_size(other_fields) > 0, do: Map.merge(payload, other_fields), else: payload

      normalized =
        data
        |> Map.take(@required_fields)
        |> Map.put(:payload, merged_payload)

      {:ok, normalized}
    else
      {:error, {:missing_fields, missing_fields}}
    end
  end

  defp normalize_data(_data), do: {:error, :invalid_data_type}

  @doc """
  订阅匹配指定路径模式的信号。

  ## 参数
  - `path_pattern` - 路径模式，如 "tool.call.**"
  - `opts` - 订阅选项
    - `:target` - 接收进程（默认 self()）

  ## 示例

      Cortex.SignalHub.subscribe("tool.call.**")
      Cortex.SignalHub.subscribe("shell.output.*", target: some_pid)
  """
  def subscribe(path_pattern, opts \\ []) do
    target = Keyword.get(opts, :target, self())
    Jido.Signal.Bus.subscribe(@bus_name, path_pattern, target: target)
  end

  @doc """
  取消订阅。
  """
  def unsubscribe(subscription_id) do
    Jido.Signal.Bus.unsubscribe(@bus_name, subscription_id)
  end

  # 自动追踪传播
  defp maybe_propagate_trace(signal, causation_id) do
    case {TraceContext.current(), causation_id} do
      {nil, nil} ->
        # 无追踪上下文且无显式 causation：保持原样
        signal

      {_ctx, cid} ->
        # 有追踪上下文或有显式 causation：传播为子 span
        case TraceContext.propagate_to(signal, cid) do
          {:ok, traced} -> traced
          {:error, _} -> signal
        end
    end
  end
end
