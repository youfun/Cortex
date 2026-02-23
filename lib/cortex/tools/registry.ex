defmodule Cortex.Tools.Registry do
  @moduledoc """
  Registry for managing LLM-accessible tools.
  Allows looking up tools by name and generating schemas for LLM providers.
  """
  use GenServer

  alias Cortex.Tools.Tool

  defstruct tools: %{}, dynamic_tools: %{}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def register(%Tool{} = tool) do
    GenServer.call(__MODULE__, {:register, tool})
  end

  def get(name) do
    GenServer.call(__MODULE__, {:get, name})
  end

  def list do
    GenServer.call(__MODULE__, :list)
  end

  @doc "运行时动态注册工具（来自 Extension）"
  def register_dynamic(%Tool{} = tool, opts \\ []) do
    source = Keyword.get(opts, :source, :extension)
    GenServer.call(__MODULE__, {:register_dynamic, tool, source})
  end

  @doc "卸载动态注册的工具"
  def unregister_dynamic(name) do
    GenServer.call(__MODULE__, {:unregister_dynamic, name})
  end

  @doc "列出所有动态注册的工具"
  def list_dynamic do
    GenServer.call(__MODULE__, :list_dynamic)
  end

  def to_llm_format(_provider \\ :openai) do
    # 合并内置工具和动态工具
    all_tools = list() ++ list_dynamic()

    all_tools
    |> Enum.map(fn tool ->
      # 构造极其标准的 JSON Schema
      properties =
        Map.new(tool.parameters, fn {name, opts} ->
          # 确保每个参数都有 description，即使没有提供 doc 也补一个
          desc = opts[:doc] || opts[:description] || "The #{name} parameter"

          # 处理类型定义，支持 :string, :integer, {:array, :string} 等
          type_schema =
            case opts[:type] do
              {:array, item_type} ->
                # 递归转换项目类型
                item_schema_type =
                  case item_type do
                    :map -> "object"
                    :list -> "array"
                    other -> to_string(other)
                  end

                %{
                  "type" => "array",
                  "items" => %{"type" => item_schema_type}
                }

              :map ->
                %{"type" => "object"}

              :list ->
                %{"type" => "array"}

              type when is_atom(type) ->
                %{"type" => to_string(type)}

              nil ->
                %{"type" => "string"}
            end

          {to_string(name), Map.put(type_schema, "description", to_string(desc))}
        end)

      required_fields =
        tool.parameters
        |> Enum.filter(fn {_, opts} -> opts[:required] end)
        |> Enum.map(fn {name, _} -> to_string(name) end)

      parameters_schema = %{
        "type" => "object",
        "properties" => properties,
        "required" => required_fields
      }

      ReqLLM.Tool.new!(
        name: tool.name,
        description: tool.description,
        parameter_schema: parameters_schema,
        callback: &noop_callback/1
      )
    end)
  end

  defp noop_callback(_args), do: {:ok, %{}}

  # Callbacks

  @impl true
  def init(_) do
    # 异步注册内置工具，避免阻塞启动
    send(self(), :register_built_in)
    {:ok, %{tools: %{}, dynamic_tools: %{}}}
  end

  @impl true
  def handle_info(:register_built_in, state) do
    new_state =
      [
        # === V3 核心 4+1 工具 ===
        %Tool{
          name: "read_file",
          description: "Read the content of a file. Always read before editing.",
          parameters: [
            path: [type: :string, required: true, doc: "The path to the file"]
          ],
          module: Cortex.Tools.Handlers.ReadFile
        },
        %Tool{
          name: "write_file",
          description: "Write content to a file. Creates new file or overwrites existing one.",
          parameters: [
            path: [type: :string, required: true, doc: "The path to the file"],
            content: [type: :string, required: true, doc: "Content to write to the file"]
          ],
          module: Cortex.Tools.Handlers.WriteFile
        },
        %Tool{
          name: "edit_file",
          description:
            "Replace an exact string in a file with a new one. Read the file first to get exact content.",
          parameters: [
            path: [type: :string, required: true, doc: "The path to the file"],
            old_string: [type: :string, required: true, doc: "The exact string to be replaced"],
            new_string: [type: :string, required: true, doc: "The new string to replace with"]
          ],
          module: Cortex.Tools.Handlers.EditFile
        },
        %Tool{
          name: "shell",
          description:
            "Execute a shell command. Returns exit code and output. Dangerous commands are blocked.",
          parameters: [
            command: [type: :string, required: true, doc: "Shell command to execute"],
            timeout: [type: :integer, required: false, doc: "Timeout in ms (default: 30000)"]
          ],
          module: Cortex.Tools.Handlers.ShellCommand
        },
        # === Token 优化工具 ===
        %Tool{
          name: "read_file_structure",
          description:
            "Extract code structure (modules, functions, types) without implementation bodies. Use this for code exploration to save tokens. Falls back to preview for unsupported file types.",
          parameters: [
            path: [type: :string, required: true, doc: "The path to the file"]
          ],
          module: Cortex.Tools.Handlers.ReadStructure
        },
        %Tool{
          name: "bcc_extract",
          description:
            "Extract FileRecord JSON (AST structure) from source code (Elixir/TypeScript/PHP).",
          parameters: [
            path: [type: :string, required: true, doc: "The path to the source file"],
            mode: [
              type: :string,
              required: false,
              doc: "Extraction mode: ast, doc, or yaml (default: ast)"
            ]
          ],
          module: Cortex.Tools.Handlers.BccExtract
        },
        %Tool{
          name: "create_proposal",
          description: "Create a memory proposal for the agent.",
          parameters: [
            content: [type: :string, required: true, doc: "The content of the proposal"],
            type: [
              type: :string,
              required: false,
              doc: "Type of proposal (fact, insight, learning, pattern, preference)"
            ],
            confidence: [type: :number, required: false, doc: "Confidence score (0.0-1.0)"],
            evidence: [type: {:array, :string}, required: false, doc: "List of evidence strings"]
          ],
          module: Cortex.Tools.Memory.CreateProposal
        },
        %Tool{
          name: "run_memory_checks",
          description: "Run memory system background checks and get maintenance suggestions.",
          parameters: [
            skip_consolidation: [
              type: :boolean,
              required: false,
              doc: "Skip consolidation check"
            ],
            skip_insights: [type: :boolean, required: false, doc: "Skip insights check"]
          ],
          module: Cortex.Tools.Memory.RunMemoryChecks
        },
        %Tool{
          name: "detect_insights",
          description: "Analyze memory statistics to detect and queue insight proposals.",
          parameters: [
            node_threshold: [
              type: :integer,
              required: false,
              doc: "Threshold for KG node count"
            ],
            obs_threshold: [
              type: :integer,
              required: false,
              doc: "Threshold for observation count"
            ]
          ],
          module: Cortex.Tools.Memory.DetectInsights
        }
      ]
      |> Enum.reduce(state, fn tool, acc ->
        %{acc | tools: Map.put(acc.tools, tool.name, tool)}
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_call({:register, tool}, _from, state) do
    new_tools = Map.put(state.tools, tool.name, tool)
    {:reply, :ok, %{state | tools: new_tools}}
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, Map.values(state.tools), state}
  end

  @impl true
  def handle_call({:register_dynamic, tool, _source}, _from, state) do
    new_dynamic_tools = Map.put(state.dynamic_tools, tool.name, tool)
    {:reply, :ok, %{state | dynamic_tools: new_dynamic_tools}}
  end

  @impl true
  def handle_call({:unregister_dynamic, name}, _from, state) do
    new_dynamic_tools = Map.delete(state.dynamic_tools, name)
    {:reply, :ok, %{state | dynamic_tools: new_dynamic_tools}}
  end

  @impl true
  def handle_call(:list_dynamic, _from, state) do
    {:reply, Map.values(state.dynamic_tools), state}
  end

  @impl true
  def handle_call({:get, name}, _from, state) do
    # 先查内置工具，再查动态工具
    result =
      case Map.fetch(state.tools, name) do
        {:ok, tool} -> {:ok, tool}
        :error -> Map.fetch(state.dynamic_tools, name)
      end

    {:reply, result, state}
  end
end
