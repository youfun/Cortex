defmodule Cortex.Memory.Subconscious do
  @moduledoc """
  潜意识 Worker —— 后台分析并生成提议。

  基于 Arbor 的双层意识架构，潜意识层在后台分析对话和活动，
  提取有价值的信息并向意识层（LLMAgent）提交提议。

  ## 职责

  - 监听系统信号（agent.chat.request, tool.result, user.input）
  - 分析对话内容，提取事实和模式
  - 生成提议并提交到意识层
  - 去重：避免重复提议

  ## 工作流程

  1. 接收信号 → 提取相关上下文
  2. 检查是否有类似提议已存在
  3. 分析内容，生成提议（调用 LLM 进行提取）
  4. 创建 Proposal 并发射 `memory.proposal.created` 信号

  ## 当前实现

  当前实现使用简单的规则提取关键信息。
  未来版本将集成 LLM 进行更智能的分析。
  """

  use GenServer
  require Logger

  alias Cortex.Memory.Proposal
  alias Cortex.Memory.SignalTypes
  alias Cortex.SignalHub

  @default_analysis_delay_ms 3000
  @min_content_length 20
  @max_proposals_per_session 10
  @explicit_memory_prefixes ["记住", "请记住", "帮我记住", "麻烦记住"]

  defstruct [
    :analysis_task,
    :timer_ref,
    recent_signals: [],
    session_proposal_count: %{}
  ]

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  手动触发分析（用于测试）。
  """
  def analyze_now(content, opts \\ []) do
    GenServer.call(__MODULE__, {:analyze, content, opts})
  end

  @doc """
  获取当前状态统计。
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc """
  清空最近信号缓存。
  """
  def clear_cache do
    GenServer.cast(__MODULE__, :clear_cache)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # 订阅相关信号
    SignalHub.subscribe("agent.chat.request")
    SignalHub.subscribe("user.input.**")
    SignalHub.subscribe("tool.result.**")

    Logger.info(
      "[Memory.Subconscious] Initialized pid=#{inspect(self())} and subscribed to signals"
    )

    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:analyze, content, opts}, _from, state) do
    proposals = perform_analysis(content, opts)
    {:reply, {:ok, proposals}, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      recent_signals_count: length(state.recent_signals),
      session_proposal_count: state.session_proposal_count,
      total_proposals: map_size(state.session_proposal_count)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_cast(:clear_cache, state) do
    {:noreply, %{state | recent_signals: [], session_proposal_count: %{}}}
  end

  # Signal Handlers

  @impl true
  def handle_info({:signal, %Jido.Signal{} = signal}, state) do
    Logger.debug(
      "[Memory.Subconscious] Received signal pid=#{inspect(self())} id=#{signal.id} type=#{signal.type}"
    )

    handle_signal(signal, state)
  end

  @impl true
  def handle_info(%Jido.Signal{} = signal, state) do
    Logger.debug(
      "[Memory.Subconscious] Received signal pid=#{inspect(self())} id=#{signal.id} type=#{signal.type}"
    )

    handle_signal(signal, state)
  end

  @impl true
  def handle_info({:analyze_delayed, content, session_id, source_signal}, state) do
    # 执行分析
    proposals = perform_analysis(content, session_id: session_id, source_signal: source_signal)

    # 更新计数
    new_count =
      Map.get(state.session_proposal_count, session_id || "global", 0) + length(proposals)

    new_state = %{
      state
      | timer_ref: nil,
        session_proposal_count:
          Map.put(state.session_proposal_count, session_id || "global", new_count)
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_info(_other, state) do
    {:noreply, state}
  end

  defp handle_signal(%Jido.Signal{type: "agent.chat.request", data: data} = signal, state) do
    content = payload_get(data, :content)
    session_id = payload_get(data, :session_id)

    {handled_explicit, new_state} = maybe_handle_explicit_memory(state, content, signal)

    new_state =
      if not handled_explicit and should_analyze?(content) do
        # 降噪：使用防抖
        schedule_debounced_analysis(new_state, content, session_id, signal)
      else
        new_state
      end

    {:noreply, cache_signal(new_state, signal)}
  end

  defp handle_signal(%Jido.Signal{type: "user.input." <> _subtype, data: data} = signal, state) do
    # UI 会先发 user.input.*，随后还会发 agent.chat.request。
    # 为避免重复分析，这里仅处理显式“记住”指令。
    content = payload_get(data, :content)

    {_handled_explicit, new_state} = maybe_handle_explicit_memory(state, content, signal)

    {:noreply, cache_signal(new_state, signal)}
  end

  defp handle_signal(%Jido.Signal{type: "agent.response", data: data} = signal, state) do
    # ⚠️ Important: do NOT analyze agent responses.
    #
    # If we analyze assistant output, we risk feeding back the LLM’s own summaries
    # (e.g. “用户偏好: …”) into memory proposals, which may then be auto-accepted and
    # persisted as observations.
    _data = data
    {:noreply, cache_signal(state, signal)}
  end

  defp handle_signal(%Jido.Signal{type: "tool.result." <> _, data: data} = signal, state) do
    # 提取工具使用模式
    tool_name = payload_get(data, :tool_name)
    result = payload_get(data, :result)

    if tool_name do
      analyze_tool_usage(tool_name, result, signal)
    end

    {:noreply, cache_signal(state, signal)}
  end

  defp handle_signal(_signal, state) do
    {:noreply, state}
  end

  # Analysis Functions

  defp perform_analysis(content, opts) when is_binary(content) do
    session_id = Keyword.get(opts, :session_id)
    source_signal = Keyword.get(opts, :source_signal)

    # 提取潜在的记忆点
    extractors = [
      &extract_preferences/1,
      &extract_facts/1,
      &extract_patterns/1,
      &extract_technologies/1,
      &extract_coding_context/1,
      &extract_project_conventions/1
    ]

    proposals =
      extractors
      |> Enum.flat_map(fn extractor -> extractor.(content) end)
      |> Enum.filter(&not_duplicate?/1)
      |> Enum.take(@max_proposals_per_session)

    # 创建提议并发射信号
    Enum.map(proposals, fn {type, extracted_content, confidence} ->
      create_and_emit_proposal(type, extracted_content, confidence, session_id, source_signal)
    end)
  end

  defp perform_analysis(_content, _opts), do: []

  # 提取偏好
  defp extract_preferences(content) do
    patterns = [
      {~r/ prefer(?:s)?\s+(?:to\s+)?(.+?)(?:\.|,|over|than|$)/i, :preference, 0.85},
      {~r/ like(?:s)?\s+(?:to\s+)?(.+?)(?:\.|,|but|however|$)/i, :preference, 0.75},
      {~r/ don't\s+like\s+(.+?)(?:\.|,|$)/i, :preference, 0.80},
      {~r/ hate(?:s)?\s+(.+?)(?:\.|,|$)/i, :preference, 0.85},
      {~r/ enjoy(?:s)?\s+(.+?)(?:\.|,|$)/i, :preference, 0.75}
    ]

    english =
      Enum.flat_map(patterns, fn {regex, type, confidence} ->
        Regex.scan(regex, content, capture: :all_but_first)
        |> Enum.map(fn [match] ->
          cleaned = String.trim(match)
          {type, "用户偏好: #{cleaned}", confidence}
        end)
      end)

    chinese = extract_chinese_preferences(content)

    english ++ chinese
  end

  # 提取事实
  defp extract_facts(content) do
    patterns = [
      {~r/\busing\s+([A-Z][a-zA-Z0-9]*(?:\.js|\.ts|\.py|\.ex)?)\b/, :fact, 0.70},
      {~r/\bbuilding\s+(?:a|an)\s+(.+?)(?:\.|,|$)/i, :fact, 0.65},
      {~r/\bdeadline\s+(?:is\s+)?(.+?)(?:\.|,|$)/i, :fact, 0.85},
      {~r/\bworking\s+on\s+(.+?)(?:\.|,|$)/i, :fact, 0.75}
    ]

    Enum.flat_map(patterns, fn {regex, type, confidence} ->
      Regex.scan(regex, content, capture: :all_but_first)
      |> Enum.map(fn [match] ->
        cleaned = String.trim(match)
        {type, "事实: #{cleaned}", confidence}
      end)
    end)
  end

  # 提取模式
  defp extract_patterns(content) do
    # 检测重复的行为模式
    if String.contains?(content, ["always", "usually", "typically", "every time"]) do
      [
        {:pattern, "检测到行为模式", 0.60}
      ]
    else
      []
    end
  end

  # 提取技术栈
  defp extract_technologies(content) do
    # 常见技术栈关键词
    tech_keywords = [
      {"React", 0.80},
      {"Vue", 0.80},
      {"Angular", 0.80},
      {"Next.js", 0.85},
      {"Nuxt", 0.85},
      {"Tailwind", 0.80},
      {"Bootstrap", 0.80},
      {"TypeScript", 0.80},
      {"Elixir", 0.80},
      {"Phoenix", 0.85},
      {"Supabase", 0.85},
      {"PostgreSQL", 0.80},
      {"MongoDB", 0.80},
      {"Redis", 0.80},
      {"Docker", 0.75},
      {"Kubernetes", 0.80}
    ]

    content_down = String.downcase(content || "")

    matched =
      Enum.flat_map(tech_keywords, fn {tech, confidence} ->
        if String.contains?(content_down, String.downcase(tech)) do
          [{tech, confidence}]
        else
          []
        end
      end)

    case matched do
      [] ->
        []

      [{tech, confidence}] ->
        [{:fact, "使用技术: #{tech}", confidence}]

      many ->
        techs = Enum.map_join(many, "/", &elem(&1, 0))
        confidence = many |> Enum.max_by(&elem(&1, 1)) |> elem(1)
        [{:fact, "使用技术: #{techs}", confidence}]
    end
  end

  # 提取编码上下文（项目结构、架构决策、调试模式）
  defp extract_coding_context(content) do
    content_str = content || ""

    patterns = [
      # 架构/设计决策
      {~r/(?:use|adopt|switch\s+to|migrate\s+to)\s+([A-Z][a-zA-Z0-9.]+)\s+(?:for|as|instead)/i,
       :fact, 0.80},
      # 文件结构偏好
      {~r/(?:put|place|move|organize)\s+.{1,30}?\s+(?:in|under|into)\s+((?:lib|src|test|app|priv)\/[^\s,]+)/i,
       :preference, 0.75},
      # 命名约定
      {~r/(?:name|call|rename)\s+(?:it|the\s+\w+)\s+(\w+(?:_\w+)+)/i, :preference, 0.65},
      # 错误修复模式
      {~r/(?:fix|resolve|patch)\s+(?:the\s+)?(.+?)\s+(?:error|bug|issue|problem)/i, :fact, 0.70},
      # 测试偏好
      {~r/(?:test|spec)\s+(?:with|using)\s+([A-Za-z][a-zA-Z0-9_.]+)/i, :preference, 0.75}
    ]

    # 中文编码上下文
    cn_patterns = [
      {~r/(?:项目|工程)(?:用|使用|基于)\s*(.+?)(?:框架|架构|技术栈)/u, :fact, 0.85},
      {~r/(?:代码|编码)(?:风格|规范|标准)(?:用|使用|遵循)\s*(.+)/u, :preference, 0.80},
      {~r/(?:放到|放在|移到|移动到)\s*((?:lib|src|test|app|priv)\/[^\s,，。]+)/u, :preference, 0.75},
      {~r/(?:不要|禁止|避免)(?:使用|用)\s*(.+?)(?:。|，|$)/u, :preference, 0.80}
    ]

    all_patterns = patterns ++ cn_patterns

    Enum.flat_map(all_patterns, fn {regex, type, confidence} ->
      Regex.scan(regex, content_str, capture: :all_but_first)
      |> Enum.map(fn [match] ->
        cleaned = String.trim(match)
        label = if type == :preference, do: "编码偏好", else: "项目事实"
        {type, "#{label}: #{cleaned}", confidence}
      end)
    end)
  end

  # 提取项目约定（从工具调用结果中学习）
  defp extract_project_conventions(content) do
    content_str = content || ""

    results = []

    # 检测 mix.exs / package.json 等项目配置提及
    results =
      if String.contains?(content_str, "mix.exs") do
        [{:fact, "项目类型: Elixir/Mix 项目", 0.90} | results]
      else
        results
      end

    results =
      if String.contains?(content_str, "package.json") do
        [{:fact, "项目类型: Node.js 项目", 0.90} | results]
      else
        results
      end

    # 检测 OTP 模式
    results =
      if Regex.match?(~r/GenServer|Supervisor|Agent|Task\.Supervisor/i, content_str) do
        [{:fact, "使用 OTP 模式", 0.75} | results]
      else
        results
      end

    # 检测测试框架
    results =
      if Regex.match?(~r/ExUnit|mix test|pytest|jest|vitest|rspec/i, content_str) do
        case Regex.run(~r/(ExUnit|pytest|jest|vitest|rspec)/i, content_str) do
          [_, framework] -> [{:fact, "测试框架: #{framework}", 0.80} | results]
          _ -> results
        end
      else
        results
      end

    results
  end

  defp payload_get(data, key) when is_map(data) do
    payload =
      case data do
        %{payload: p} when is_map(p) -> p
        %{"payload" => p} when is_map(p) -> p
        _ -> %{}
      end

    Map.get(payload, key) ||
      Map.get(payload, to_string(key)) ||
      Map.get(data, key) ||
      Map.get(data, to_string(key))
  end

  # 分析工具使用
  defp analyze_tool_usage("read_file", result, source_signal) do
    maybe_create_file_access_proposal("read_file", result, source_signal)
  end

  defp analyze_tool_usage("read_file_structure", result, source_signal) do
    maybe_create_file_access_proposal("read_file_structure", result, source_signal)
  end

  defp analyze_tool_usage("edit_file", result, source_signal) do
    maybe_create_file_access_proposal("edit_file", result, source_signal)
  end

  defp analyze_tool_usage("write_file", result, source_signal) do
    maybe_create_write_file_proposal(result, source_signal)
  end

  defp analyze_tool_usage("shell", result, source_signal) do
    maybe_create_shell_usage_proposal(result, source_signal)
  end

  defp analyze_tool_usage(_tool_name, _result, _source_signal), do: :ok

  defp maybe_create_write_file_proposal(result, source_signal) when is_map(result) do
    if Map.has_key?(result, "path") do
      create_proposal(:fact, "创建了文件: #{result["path"]}", 0.70, source_signal)
    else
      :ok
    end
  end

  defp maybe_create_write_file_proposal(_result, _source_signal), do: :ok

  defp maybe_create_file_access_proposal(tool_name, result, source_signal) when is_map(result) do
    path = Map.get(result, "path") || Map.get(result, :path)

    if path do
      # Track frequently accessed directories as project structure knowledge
      dir = Path.dirname(path)

      if dir != "." and String.length(dir) > 1 do
        create_proposal(:fact, "活跃目录: #{dir} (#{tool_name})", 0.55, source_signal)
      else
        :ok
      end
    else
      :ok
    end
  end

  defp maybe_create_file_access_proposal(_tool_name, _result, _source_signal), do: :ok

  defp maybe_create_shell_usage_proposal(result, source_signal) when is_map(result) do
    with cmd when is_binary(cmd) <- Map.get(result, "command"),
         true <- String.contains?(cmd, ["git", "mix", "npm", "docker"]) do
      create_proposal(:pattern, "使用命令: #{cmd}", 0.60, source_signal)
    else
      _ -> :ok
    end
  end

  defp maybe_create_shell_usage_proposal(_result, _source_signal), do: :ok

  # 创建提议并发射信号
  defp create_and_emit_proposal(type, content, confidence, session_id, source_signal) do
    source_signal_id = if source_signal, do: source_signal.id

    {:ok, proposal} =
      Proposal.create(content,
        type: type,
        confidence: confidence,
        source_context: %{
          session_id: session_id,
          source_signal_id: source_signal_id
        },
        evidence: ["Subconscious Analysis"]
      )

    # 发射信号
    emit_proposal_created(proposal, session_id, source_signal)
    proposal
  end

  defp create_proposal(type, content, confidence, source_signal) do
    source_signal_id = if source_signal, do: source_signal.id

    Proposal.create(content,
      type: type,
      confidence: confidence,
      source_context: %{
        source_signal_id: source_signal_id
      },
      evidence: ["Tool Usage Analysis"]
    )
  end

  # 检查是否重复
  defp not_duplicate?({_type, content, _confidence}) do
    case Proposal.find_similar(content, threshold: 0.85) do
      nil -> true
      _existing -> false
    end
  end

  # 辅助函数

  defp should_analyze?(nil), do: false

  defp should_analyze?(content) when is_binary(content) do
    String.length(content) >= @min_content_length or contains_chinese_preference?(content)
  end

  defp contains_chinese_preference?(content) do
    String.contains?(content, ["喜欢", "偏好", "常用", "倾向", "不喜欢", "讨厌"])
  end

  defp extract_chinese_preferences(content) when is_binary(content) do
    clauses = split_chinese_clauses(content)

    Enum.flat_map(clauses, fn clause ->
      clause = String.trim(clause)

      cond do
        clause == "" ->
          []

        interrogative_preference_clause?(clause) ->
          []

        String.contains?(clause, ["不喜欢", "讨厌"]) ->
          case Regex.run(~r/(?:不喜欢|讨厌)\s*([^。！？;；,，]+)/u, clause, capture: :all_but_first) do
            [match] when is_binary(match) ->
              cleaned = match |> String.trim() |> clean_chinese_preference_object()
              if cleaned == "", do: [], else: [{:preference, "用户不喜欢: #{cleaned}", 0.82}]

            _ ->
              []
          end

        String.contains?(clause, ["喜欢", "偏好", "常用", "倾向"]) ->
          case Regex.run(
                 ~r/(?:喜欢|偏好|常用|倾向)(?:使用|用|的是)?\s*([^。！？;；,，]+)/u,
                 clause,
                 capture: :all_but_first
               ) do
            [match] when is_binary(match) ->
              cleaned = match |> String.trim() |> clean_chinese_preference_object()
              if cleaned == "", do: [], else: [{:preference, "用户偏好: #{cleaned}", 0.85}]

            _ ->
              []
          end

        true ->
          []
      end
    end)
  end

  defp extract_chinese_preferences(_), do: []

  defp split_chinese_clauses(content) do
    String.split(content, ~r/[。！？;；,，]/u, trim: true)
  end

  defp interrogative_preference_clause?(clause) when is_binary(clause) do
    c = String.trim(clause)

    # Avoid false positives like:
    # - "我喜欢吃什么"  -> should be a question, not a preference
    # - "你喜欢什么"    -> asking assistant, not stating user preference
    # - "喜欢什么呢"    -> vague question
    preference_cue? = String.contains?(c, ["喜欢", "偏好", "常用", "倾向", "不喜欢", "讨厌"])

    interrogative_cue? =
      String.contains?(c, ["什么", "哪", "哪里", "怎么", "为何", "为什么", "吗", "么"]) or
        String.ends_with?(c, "呢")

    preference_cue? and interrogative_cue?
  end

  defp interrogative_preference_clause?(_), do: false

  defp clean_chinese_preference_object(obj) when is_binary(obj) do
    obj
    |> String.trim()
    |> String.replace(~r/^(?:是|为)\s*/u, "")
    |> String.trim()
  end

  defp maybe_handle_explicit_memory(state, nil, _signal), do: {false, state}

  defp maybe_handle_explicit_memory(state, content, signal) when is_binary(content) do
    case extract_explicit_memory(content) do
      {:ok, remembered} ->
        Logger.info("[Memory.Subconscious] Explicit memory received: #{remembered}")
        # 直接写入观察项，跳过提议流程
        # 作为显式指令，优先级设为高
        _ =
          Cortex.Memory.Store.append_observation(remembered,
            priority: :high,
            source_signal_id: signal.id
          )

        Logger.info("[Memory.Subconscious] Explicit memory stored via Memory.Store")
        {true, state}

      :noop ->
        {false, state}
    end
  end

  defp extract_explicit_memory(content) do
    trimmed = String.trim(content)

    if Enum.any?(@explicit_memory_prefixes, &String.starts_with?(trimmed, &1)) do
      # 支持: "记住这条: xxx", "记住：xxx", "记住 xxx"
      case Regex.run(
             ~r/^(?:记住|请记住|帮我记住|麻烦记住)(?:这条)?[:：]?\s*(.+)$/u,
             trimmed,
             capture: :all_but_first
           ) do
        [remembered] when is_binary(remembered) ->
          cleaned = String.trim(remembered)
          if cleaned == "", do: :noop, else: {:ok, cleaned}

        _ ->
          :noop
      end
    else
      :noop
    end
  end

  defp schedule_debounced_analysis(state, content, session_id, source_signal) do
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    timer_ref =
      Process.send_after(
        self(),
        {:analyze_delayed, content, session_id, source_signal},
        @default_analysis_delay_ms
      )

    %{state | timer_ref: timer_ref}
  end

  defp cache_signal(state, signal) do
    # 保留最近 100 个信号用于上下文
    recent = Enum.take([signal | state.recent_signals], 100)
    %{state | recent_signals: recent}
  end

  defp emit_proposal_created(proposal, session_id, source_signal) do
    source_meta =
      case source_signal do
        %Jido.Signal{} = sig ->
          %{
            source_signal_id: sig.id,
            source_signal_type: sig.type,
            source_actor: payload_get(sig.data, :actor),
            source_provider: payload_get(sig.data, :provider)
          }

        _ ->
          %{}
      end

    data =
      %{
        provider: "memory",
        event: "proposal",
        action: "create",
        actor: "subconscious_engine",
        origin: %{
          channel: "memory",
          client: "subconscious",
          platform: "server",
          session_id: session_id
        },
        proposal_id: proposal.id,
        type: proposal.type,
        content_preview: String.slice(proposal.content, 0, 200),
        confidence: proposal.confidence,
        session_id: session_id
      }
      |> Map.merge(source_meta)

    SignalHub.emit(SignalTypes.memory_proposal_created(), data, source: "/memory/subconscious")
  end
end
