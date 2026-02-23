defmodule Cortex.Tools.Handlers.ReadStructure.GoParser do
  @moduledoc false

  # Golang 正则提取
  def extract(content) do
    lines = String.split(content, "\n")

    # 提取 package、import、type、func、const、var 声明
    structure_lines =
      lines
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _idx} ->
        trimmed = String.trim_leading(line)

        # 匹配方法定义 func (receiver) MethodName
        String.starts_with?(trimmed, [
          "package ",
          "import ",
          "type ",
          "func ",
          "const ",
          "var "
        ]) or
          Regex.match?(~r/^func\s+\(\w+\s+\*?\w+\)\s+\w+/, trimmed)
      end)
      |> Enum.map(fn {line, idx} ->
        # 对于函数，只保留签名，移除函数体
        cleaned =
          cond do
            String.contains?(line, "func ") ->
              # 提取到 { 之前的部分
              case String.split(line, "{", parts: 2) do
                [signature | _] -> String.trim(signature)
                _ -> String.trim(line)
              end

            true ->
              String.trim(line)
          end

        "#{idx}: #{cleaned}"
      end)

    header = "[Golang Structure]\n\n"
    body = Enum.join(structure_lines, "\n")

    if body == "" do
      header <> "(No package/type/func definitions found)"
    else
      header <> body
    end
  end
end
