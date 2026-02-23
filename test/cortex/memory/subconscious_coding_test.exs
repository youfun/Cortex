defmodule Cortex.Memory.SubconsciousCodingTest do
  use ExUnit.Case, async: false

  alias Cortex.Memory.Proposal
  alias Cortex.Memory.Subconscious
  alias Cortex.Memory.Store

  setup do
    Proposal.clear_all()

    unless Process.whereis(Store) do
      start_supervised!(Store)
    end

    unless Process.whereis(Subconscious) do
      start_supervised!(Subconscious)
    end

    if Process.whereis(Subconscious), do: Subconscious.clear_cache()
    if Process.whereis(Store), do: Store.clear_all()

    :ok
  end

  describe "extract_coding_context — architecture decisions" do
    test "extracts 'use X for Y' patterns" do
      {:ok, proposals} = Subconscious.analyze_now("We should use GenServer for state management", [])
      contents = Enum.map(proposals, & &1.content)
      assert Enum.any?(contents, &String.contains?(&1, "GenServer"))
    end

    test "extracts Chinese coding preferences" do
      {:ok, proposals} = Subconscious.analyze_now("项目用Phoenix框架，代码风格遵循Credo", [])
      contents = Enum.map(proposals, & &1.content)
      assert Enum.any?(contents, &String.contains?(&1, "Phoenix"))
    end

    test "extracts 'avoid/禁止' patterns" do
      {:ok, proposals} = Subconscious.analyze_now("不要使用全局变量", [])
      contents = Enum.map(proposals, & &1.content)
      assert Enum.any?(contents, &String.contains?(&1, "全局变量"))
    end

    test "extracts file path placement preferences" do
      {:ok, proposals} = Subconscious.analyze_now("put the module in lib/cortex/memory/", [])
      contents = Enum.map(proposals, & &1.content)
      assert Enum.any?(contents, &String.contains?(&1, "lib/cortex/memory"))
    end

    test "extracts Chinese file path placement" do
      {:ok, proposals} = Subconscious.analyze_now("放到lib/cortex/tools/目录下", [])
      contents = Enum.map(proposals, & &1.content)
      assert Enum.any?(contents, &String.contains?(&1, "lib/cortex/tools"))
    end
  end

  describe "extract_project_conventions — project type detection" do
    test "detects Elixir/Mix project" do
      {:ok, proposals} = Subconscious.analyze_now("Check the mix.exs for dependencies", [])
      contents = Enum.map(proposals, & &1.content)
      assert Enum.any?(contents, &String.contains?(&1, "Elixir/Mix"))
    end

    test "detects Node.js project" do
      {:ok, proposals} = Subconscious.analyze_now("Update the package.json with new deps", [])
      contents = Enum.map(proposals, & &1.content)
      assert Enum.any?(contents, &String.contains?(&1, "Node.js"))
    end

    test "detects OTP patterns" do
      {:ok, proposals} = Subconscious.analyze_now("We need a GenServer and a Supervisor tree", [])
      contents = Enum.map(proposals, & &1.content)
      assert Enum.any?(contents, &String.contains?(&1, "OTP"))
    end

    test "detects test framework" do
      {:ok, proposals} = Subconscious.analyze_now("Run mix test with ExUnit assertions", [])
      contents = Enum.map(proposals, & &1.content)
      assert Enum.any?(contents, &String.contains?(&1, "ExUnit"))
    end

    test "detects jest test framework" do
      {:ok, proposals} = Subconscious.analyze_now("We use jest for unit testing", [])
      contents = Enum.map(proposals, & &1.content)
      assert Enum.any?(contents, &String.contains?(&1, "jest"))
    end
  end

  describe "extract_technologies — enhanced tech detection" do
    test "extracts multiple technologies" do
      {:ok, proposals} =
        Subconscious.analyze_now("Building with React, TypeScript and Tailwind", [])

      contents = Enum.map(proposals, & &1.content)
      assert Enum.any?(contents, &String.contains?(&1, "React"))
      assert Enum.any?(contents, &String.contains?(&1, "TypeScript"))
    end

    test "extracts Elixir ecosystem" do
      {:ok, proposals} = Subconscious.analyze_now("Using Elixir with Phoenix and PostgreSQL", [])
      contents = Enum.map(proposals, & &1.content)
      assert Enum.any?(contents, &String.contains?(&1, "Elixir"))
      assert Enum.any?(contents, &String.contains?(&1, "Phoenix"))
    end
  end

  describe "tool usage analysis — file access tracking" do
    test "tracks read_file tool usage via signal" do
      signal = %Jido.Signal{
        type: "tool.result.read_file",
        id: "test-tool-read",
        source: "test",
        data: %{
          tool_name: "read_file",
          result: %{"path" => "lib/cortex/agents/llm_agent.ex"}
        }
      }

      send(Subconscious, {:signal, signal})
      Process.sleep(200)

      # Should create a proposal about the active directory
      pending = Proposal.list_pending(limit: 50)
      contents = Enum.map(pending, & &1.content)
      assert Enum.any?(contents, &String.contains?(&1, "lib/cortex/agents"))
    end

    test "tracks edit_file tool usage via signal" do
      signal = %Jido.Signal{
        type: "tool.result.edit_file",
        id: "test-tool-edit",
        source: "test",
        data: %{
          tool_name: "edit_file",
          result: %{"path" => "lib/cortex/memory/store.ex"}
        }
      }

      send(Subconscious, {:signal, signal})
      Process.sleep(200)

      pending = Proposal.list_pending(limit: 50)
      contents = Enum.map(pending, & &1.content)
      assert Enum.any?(contents, &String.contains?(&1, "lib/cortex/memory"))
    end
  end
end
