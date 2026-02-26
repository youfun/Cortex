defmodule Cortex.BDD.Instructions.V1 do
  @moduledoc "Cortex BDD v1 指令运行时实现"

  @modules [
    Cortex.BDD.Instructions.V1.Signal,
    Cortex.BDD.Instructions.V1.Agent,
    Cortex.BDD.Instructions.V1.Tool,
    Cortex.BDD.Instructions.V1.Memory,
    Cortex.BDD.Instructions.V1.Permission,
    Cortex.BDD.Instructions.V1.Session,
    Cortex.BDD.Instructions.V1.Config
  ]

  @type ctx :: map()
  @type meta :: map()

  @spec capabilities() :: MapSet.t(atom())
  def capabilities do
    Enum.reduce(@modules, MapSet.new(), fn module, acc ->
      MapSet.union(acc, module.capabilities())
    end)
  end

  @spec new_run_id() :: String.t()
  def new_run_id do
    "bdd_run_" <> Integer.to_string(System.unique_integer([:positive]))
  end

  @doc """
  获取上下文中的变量值，如果不存在则抛出异常。
  由 bddc 生成的代码在处理 $var 引用时调用。
  """
  def get!(ctx, key, _meta) do
    case Map.fetch(ctx, key) do
      {:ok, value} ->
        value

      :error ->
        raise "Variable $#{key} not found in BDD context. Available keys: #{inspect(Map.keys(ctx))}"
    end
  end

  @spec run_step!(ctx(), :given | :when | :then, atom(), map(), meta(), term()) :: ctx()
  def run_step!(ctx, kind, name, args, meta, _step_id \\ nil) do
    run!(ctx, kind, name, args, meta)
  end

  @spec run!(ctx(), :given | :when | :then, atom(), map(), meta()) :: ctx()
  def run!(ctx, kind, name, args, _meta \\ %{}) do
    case dispatch(ctx, kind, name, args) do
      {:ok, new_ctx} ->
        new_ctx

      :no_match ->
        raise ArgumentError, "未实现的指令: {#{kind}, #{name}}"
    end
  end

  defp dispatch(ctx, kind, name, args) do
    Enum.reduce_while(@modules, :no_match, fn module, _acc ->
      case module.run(ctx, kind, name, args) do
        {:ok, new_ctx} -> {:halt, {:ok, new_ctx}}
        :no_match -> {:cont, :no_match}
      end
    end)
  end
end
