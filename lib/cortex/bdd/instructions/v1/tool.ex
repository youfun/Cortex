defmodule Cortex.BDD.Instructions.V1.Tool do
  @moduledoc false

  import ExUnit.Assertions

  alias Cortex.BDD.Instructions.V1.Helpers
  alias Cortex.Extensions.HookRegistry
  alias Cortex.Extensions.Manager, as: ExtensionManager
  alias Cortex.Tools.Tool
  alias Cortex.Tools.Registry, as: ToolRegistry

  @spec capabilities() :: MapSet.t(atom())
  def capabilities do
    MapSet.new([
      :shell,
      :execute_tool,
      :register_dynamic_tool,
      :unregister_dynamic_tool,
      :assert_tool_available,
      :assert_tool_not_available,
      :load_extension,
      :unload_extension,
      :assert_extension_loaded,
      :assert_extension_not_loaded,
      :assert_hooks_registered,
      :assert_hooks_unregistered,
      :assert_tools_registered,
      :assert_tools_unregistered,
      :parse_skill_command,
      :assert_skill_command,
      :assert_tool_result
    ])
  end

  def run(ctx, kind, name, args) do
    case {kind, name} do
      {:given, :shell} ->
        command = args.command
        project_root = Map.get(ctx, :project_root, File.cwd!())

        IO.puts("[BDD Shell] Executing \"#{command}\" in #{project_root}")

        case Cortex.Sandbox.execute(command, workdir: project_root) do
          {:ok, _result} -> {:ok, ctx}
          {:error, reason} -> raise "Shell command failed: #{inspect(reason)}"
        end

      {:when, :execute_tool} ->
        tool_name = args.tool_name
        tool_args = Helpers.parse_messages(args.args)
        session_id = Map.get(ctx, :session_id, "bdd_session")
        project_root = Map.get(ctx, :project_root, File.cwd!())

        tool_ctx = %{session_id: session_id, project_root: project_root}

        case Cortex.Tools.ToolRunner.execute(tool_name, tool_args, tool_ctx) do
          {:ok, result, _elapsed_ms} -> {:ok, Map.put(ctx, :last_tool_result, result)}
          {:error, reason, _elapsed_ms} -> {:ok, Map.put(ctx, :last_tool_result, {:error, reason})}
        end

      {:when, :register_dynamic_tool} ->
        tool_name = args.tool_name
        description = Map.get(args, :description, "Dynamic tool #{tool_name}")

        tool = %Tool{
          name: tool_name,
          description: description,
          parameters: [],
          module: Cortex.TestSupport.DynamicToolHandler
        }

        :ok = ToolRegistry.register_dynamic(tool, source: :bdd)
        {:ok, Map.put(ctx, :last_dynamic_tool, tool_name)}

      {:when, :unregister_dynamic_tool} ->
        tool_name = args.tool_name
        :ok = ToolRegistry.unregister_dynamic(tool_name)
        {:ok, ctx}

      {:then, :assert_tool_available} ->
        tool_name = args.tool_name

        assert {:ok, _tool} = ToolRegistry.get(tool_name),
               "Expected tool #{tool_name} to be available"

        {:ok, ctx}

      {:then, :assert_tool_not_available} ->
        tool_name = args.tool_name

        assert ToolRegistry.get(tool_name) == :error,
               "Expected tool #{tool_name} to be unavailable"

        {:ok, ctx}

      {:when, :load_extension} ->
        module = Helpers.module_from_string(args.module)

        case ExtensionManager.load(module) do
          :ok ->
            {:ok, ctx}

          {:error, reason} ->
            raise "Failed to load extension #{inspect(module)}: #{inspect(reason)}"
        end

      {:when, :unload_extension} ->
        module = Helpers.module_from_string(args.module)

        case ExtensionManager.unload(module) do
          :ok ->
            {:ok, ctx}

          {:error, reason} ->
            raise "Failed to unload extension #{inspect(module)}: #{inspect(reason)}"
        end

      {:then, :assert_extension_loaded} ->
        module = Helpers.module_from_string(args.module)
        loaded = ExtensionManager.list_loaded()
        assert module in loaded, "Expected extension #{inspect(module)} to be loaded"
        {:ok, ctx}

      {:then, :assert_extension_not_loaded} ->
        module = Helpers.module_from_string(args.module)
        loaded = ExtensionManager.list_loaded()
        refute module in loaded, "Expected extension #{inspect(module)} to be unloaded"
        {:ok, ctx}

      {:then, :assert_hooks_registered} ->
        session_id = Map.get(args, :session_id) || Map.get(ctx, :session_id, "bdd_session")
        hooks = HookRegistry.get_hooks(session_id)
        expected = Helpers.parse_modules(args.hooks)

        Enum.each(expected, fn hook ->
          assert hook in hooks, "Expected hook #{inspect(hook)} to be registered"
        end)

        {:ok, ctx}

      {:then, :assert_hooks_unregistered} ->
        session_id = Map.get(args, :session_id) || Map.get(ctx, :session_id, "bdd_session")
        hooks = HookRegistry.get_hooks(session_id)
        expected = Helpers.parse_modules(args.hooks)

        Enum.each(expected, fn hook ->
          refute hook in hooks, "Expected hook #{inspect(hook)} to be unregistered"
        end)

        {:ok, ctx}

      {:then, :assert_tools_registered} ->
        expected = Helpers.parse_list(args.tools)
        actual_names = ToolRegistry.list_dynamic() |> Enum.map(& &1.name)

        Enum.each(expected, fn tool_name ->
          assert tool_name in actual_names, "Expected tool #{tool_name} to be registered"
        end)

        {:ok, ctx}

      {:then, :assert_tools_unregistered} ->
        expected = Helpers.parse_list(args.tools)
        actual_names = ToolRegistry.list_dynamic() |> Enum.map(& &1.name)

        Enum.each(expected, fn tool_name ->
          refute tool_name in actual_names, "Expected tool #{tool_name} to be unregistered"
        end)

        {:ok, ctx}

      {:when, :parse_skill_command} ->
        input = args.input

        parsed =
          case Cortex.Hooks.SkillInvokeHook.parse_command(input) do
            {:ok, %{name: name, args: skill_args}} ->
              %{
                matched: true,
                name: name,
                args: skill_args,
                rewritten: Cortex.Hooks.SkillInvokeHook.build_message(name, skill_args)
              }

            :no_match ->
              %{matched: false}
          end

        {:ok, Map.put(ctx, :skill_command, parsed)}

      {:then, :assert_skill_command} ->
        parsed = Map.get(ctx, :skill_command, %{})

        if Map.has_key?(args, :matched) do
          assert Map.get(parsed, :matched) == args.matched
        end

        if Map.has_key?(args, :name) and args.name do
          assert Map.get(parsed, :name) == args.name
        end

        if Map.has_key?(args, :contains) and args.contains do
          assert String.contains?(Map.get(parsed, :rewritten, ""), args.contains)
        end

        {:ok, ctx}

      {:then, :assert_tool_result} ->
        actual = Map.fetch!(ctx, :last_tool_result)
        actual_str = if is_binary(actual), do: actual, else: inspect(actual)

        if Map.has_key?(args, :contains) do
          assert actual_str =~ args.contains,
                 "Expected result to contain #{args.contains}, but got: #{inspect(actual)}"
        end

        if Map.get(args, :truncated, false) do
          assert actual_str =~ "[TRUNCATED:",
                 "Expected result to be truncated, but got: #{inspect(actual)}"
        end

        {:ok, ctx}

      _ ->
        :no_match
    end
  end
end
