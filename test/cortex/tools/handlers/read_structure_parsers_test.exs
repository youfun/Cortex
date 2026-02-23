defmodule Cortex.Tools.Handlers.ReadStructureParsersTest do
  use ExUnit.Case, async: true

  alias Cortex.Tools.Handlers.ReadStructure.ElixirParser
  alias Cortex.Tools.Handlers.ReadStructure.FallbackParser
  alias Cortex.Tools.Handlers.ReadStructure.GoParser
  alias Cortex.Tools.Handlers.ReadStructure.JsParser
  alias Cortex.Tools.Handlers.ReadStructure.PythonParser
  alias Cortex.Tools.Handlers.ReadStructure.RustParser

  describe "ElixirParser.extract/1" do
    test "extracts structure via AST" do
      content = """
      defmodule Sample.Parser do
        @moduledoc "Parser docs"

        @type state :: map()

        def run(arg), do: arg

        defp helper(x), do: x + 1
      end
      """

      result = ElixirParser.extract(content)

      assert result =~ "defmodule Sample.Parser"
      assert result =~ "@moduledoc"
      assert result =~ "@type"
      assert result =~ "def run/1"
      assert result =~ "defp helper/1"
    end

    test "falls back to regex on syntax error" do
      content = """
      defmodule Broken do
        def broken(
      end
      """

      result = ElixirParser.extract(content)

      assert result =~ "Regex Fallback"
      assert result =~ "defmodule Broken"
    end
  end

  describe "JsParser.extract/1" do
    test "extracts JS/TS structures" do
      content = """
      export function run() { return 1; }
      export class Service {}
      interface User { id: string }
      """

      result = JsParser.extract(content)

      assert result =~ "JavaScript/TypeScript Structure"
      assert result =~ "export function run"
      assert result =~ "export class Service"
      assert result =~ "interface User"
    end
  end

  describe "RustParser.extract/1" do
    test "extracts Rust structures" do
      content = """
      pub struct User { id: i32 }
      trait Repo {}
      fn run() {}
      """

      result = RustParser.extract(content)

      assert result =~ "Rust Structure"
      assert result =~ "pub struct User"
      assert result =~ "trait Repo"
      assert result =~ "fn run"
    end
  end

  describe "PythonParser.extract/1" do
    test "extracts python structure" do
      content = """
      from typing import Optional

      class Service:
          def run(self):
              return 1

      def helper():
          return 2
      """

      result = PythonParser.extract(content)

      assert result =~ "Python Structure"
      assert result =~ "from typing import Optional"
      assert result =~ "class Service"
      assert result =~ "def run"
      assert result =~ "def helper"
      refute result =~ "return 1"
    end

    test "returns no definitions message for empty file" do
      content = "# comment only"

      result = PythonParser.extract(content)

      assert result =~ "No class/function definitions found"
    end
  end

  describe "GoParser.extract/1" do
    test "extracts go structure and trims func body" do
      content = """
      package main

      type Service struct {}

      func (s *Service) Run() {
        println("ok")
      }
      """

      result = GoParser.extract(content)

      assert result =~ "Golang Structure"
      assert result =~ "package main"
      assert result =~ "type Service struct"
      assert result =~ "func (s *Service) Run()"
      refute result =~ "println"
    end

    test "returns no definitions message for empty file" do
      content = "// only comment"

      result = GoParser.extract(content)

      assert result =~ "No package/type/func definitions found"
    end
  end

  describe "FallbackParser.extract/2" do
    test "renders preview and caps to 50 lines" do
      lines = Enum.map(1..60, fn idx -> "line-#{idx}" end)
      content = Enum.join(lines, "\n")

      result = FallbackParser.extract(content, "data.bin")

      assert result =~ "Unsupported File Type"
      assert result =~ "File: data.bin"
      assert result =~ "Lines: 60"
      assert result =~ "line-50"
      refute result =~ "line-51"
    end
  end
end
