defmodule Cortex.Tools.Handlers.ReadStructure.PythonParser do
  @moduledoc false

  # Python 正则提取（参考 fastcode 的 get_file_structure_summary）
  def extract(content) do
    lines = String.split(content, "\n")

    # 提取类定义、函数定义、装饰器、import 语句
    structure_lines =
      lines
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _idx} ->
        trimmed = String.trim_leading(line)

        # 匹配类、函数、装饰器、import
        # 匹配类型提示（如 TypeVar, Protocol）
        String.starts_with?(trimmed, ["class ", "def ", "async def ", "@", "from ", "import "]) or
          Regex.match?(~r/^[A-Z]\w+\s*=\s*/, trimmed)
      end)
      |> Enum.map(fn {line, idx} ->
        # 移除函数体，只保留签名
        cleaned =
          line
          |> String.replace(~r/:\s*$/, ":")
          |> String.trim_trailing()

        "#{idx}: #{cleaned}"
      end)

    header = "[Python Structure]\n\n"
    body = Enum.join(structure_lines, "\n")

    if body == "" do
      header <> "(No class/function definitions found)"
    else
      header <> body
    end
  end
end
