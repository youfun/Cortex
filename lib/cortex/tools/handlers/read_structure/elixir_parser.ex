defmodule Cortex.Tools.Handlers.ReadStructure.ElixirParser do
  @moduledoc false

  def extract(content) do
    case Code.string_to_quoted(content) do
      {:ok, quoted} ->
        metadata = extract_metadata(quoted)
        format_elixir_metadata(metadata)

      {:error, _} ->
        # 语法错误回退到正则模式
        extract_fallback(content)
    end
  end

  defp extract_metadata(quoted) do
    {_ast, acc} =
      Macro.prewalk(quoted, [], fn
        # 模块定义
        {:defmodule, meta, [name, [do: block]]} = node, acc ->
          moduledoc = extract_moduledoc(block)
          {node, [{:module, name, moduledoc, meta} | acc]}

        # 协议
        {:defprotocol, meta, [name, _]} = node, acc ->
          {node, [{:protocol, name, meta} | acc]}

        # 协议实现
        {:defimpl, meta, [name, opts | _]} = node, acc ->
          for_type = Keyword.get(opts, :for)
          {node, [{:impl, name, for_type, meta} | acc]}

        # 公开函数
        {:def, meta, [{name, _, args} | _]} = node, acc ->
          {node, [{:func, :public, name, arity(args), meta} | acc]}

        # 私有函数
        {:defp, meta, [{name, _, args} | _]} = node, acc ->
          {node, [{:func, :private, name, arity(args), meta} | acc]}

        # 宏
        {:defmacro, meta, [{name, _, args} | _]} = node, acc ->
          {node, [{:macro, name, arity(args), meta} | acc]}

        # use/import/alias/require
        {directive, meta, _} = node, acc when directive in ~w(use import alias require)a ->
          {node, [{:directive, directive, node, meta} | acc]}

        # @spec, @type, @typep, @doc, @moduledoc
        {:@, meta, [{attr, _, _} = spec]} = node, acc
        when attr in ~w(spec type typep doc moduledoc)a ->
          {node, [{:attribute, attr, spec, meta} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(acc)
  end

  defp extract_moduledoc({:__block__, _, exprs}) do
    Enum.find_value(exprs, fn
      {:@, _, [{:moduledoc, _, [doc]}]} when is_binary(doc) -> doc
      _ -> nil
    end)
  end

  defp extract_moduledoc(_), do: nil

  defp arity(nil), do: 0
  defp arity(args) when is_list(args), do: length(args)
  defp arity(_), do: 0

  defp format_elixir_metadata(metadata) do
    sections =
      metadata
      |> Enum.group_by(&elem(&1, 0))
      |> Enum.map(&format_section/1)
      |> Enum.reject(&(&1 == ""))

    Enum.join(sections, "\n\n")
  end

  defp format_section({:module, items}) do
    items
    |> Enum.map(fn {:module, name, doc, _meta} ->
      doc_str = if doc, do: "\n  @moduledoc \"#{String.slice(doc, 0, 100)}...\"", else: ""
      "defmodule #{format_name(name)} do#{doc_str}\nend"
    end)
    |> Enum.join("\n\n")
  end

  defp format_section({:protocol, items}) do
    items
    |> Enum.map(fn {:protocol, name, _meta} ->
      "defprotocol #{format_name(name)} do\nend"
    end)
    |> Enum.join("\n\n")
  end

  defp format_section({:impl, items}) do
    items
    |> Enum.map(fn {:impl, name, for_type, _meta} ->
      "defimpl #{format_name(name)}, for: #{inspect(for_type)} do\nend"
    end)
    |> Enum.join("\n\n")
  end

  defp format_section({:func, items}) do
    items
    |> Enum.map(fn {:func, visibility, name, arity, _meta} ->
      func_type = if visibility == :public, do: "def", else: "defp"
      "#{func_type} #{name}/#{arity}"
    end)
    |> Enum.join("\n")
  end

  defp format_section({:macro, items}) do
    items
    |> Enum.map(fn {:macro, name, arity, _meta} ->
      "defmacro #{name}/#{arity}"
    end)
    |> Enum.join("\n")
  end

  defp format_section({:directive, items}) do
    items
    |> Enum.map(fn {:directive, _type, node, _meta} ->
      Macro.to_string(node)
    end)
    |> Enum.join("\n")
  end

  defp format_section({:attribute, items}) do
    items
    |> Enum.map(fn {:attribute, _attr, spec, _meta} ->
      "@" <> Macro.to_string(spec)
    end)
    |> Enum.join("\n")
  end

  defp format_section(_), do: ""

  defp format_name({:__aliases__, _, parts}), do: Enum.join(parts, ".")
  defp format_name(name) when is_atom(name), do: to_string(name)
  defp format_name(name), do: inspect(name)

  # Elixir 正则降级
  defp extract_fallback(content) do
    patterns = [
      ~r/^defmodule\s+([\w\.]+)/m,
      ~r/^def\s+(\w+)/m,
      ~r/^defp\s+(\w+)/m,
      ~r/^defmacro\s+(\w+)/m,
      ~r/^@(spec|type|typep)\s+/m
    ]

    matches =
      patterns
      |> Enum.flat_map(&Regex.scan(&1, content))
      |> Enum.map(&List.first/1)
      |> Enum.uniq()

    "[Elixir Structure - Regex Fallback]\n\n" <> Enum.join(matches, "\n")
  end
end
