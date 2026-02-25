defmodule Cortex.BDD.Instructions.V1.Config do
  @moduledoc false

  import ExUnit.Assertions

  alias Cortex.Config.SearchSettings
  alias Cortex.Config.Settings
  alias Cortex.Tools.ToolInterceptor

  @spec capabilities() :: MapSet.t(atom())
  def capabilities do
    MapSet.new([
      # folder_authorization.dsl stubs
      :check_folder_access,
      :add_authorized_folder,
      :remove_authorized_folder,
      :assert_folder_access,
      # tool interceptor
      :tool_interceptor_initialized,
      :tool_pre_approved,
      :check_tool_approval,
      :approval_required,
      :approval_not_required,
      # search settings
      :search_settings_clean,
      :get_search_settings,
      :update_search_provider,
      :search_provider_is,
      :validation_error,
      # title generation
      :title_settings_clean,
      :get_title_mode,
      :set_title_mode,
      :trigger_title_generation,
      :title_mode_is,
      :title_generation_skipped
    ])
  end

  def run(ctx, kind, name, args) do
    case {kind, name} do
      # ---- folder_authorization stubs ----
      {:when, :check_folder_access} ->
        result = if args.mode == "unrestricted", do: :ok, else: check_whitelist(ctx, args)
        {:ok, Map.put(ctx, :last_folder_access, result)}

      {:given, :add_authorized_folder} ->
        folders = Map.get(ctx, :authorized_folders, %{})
        agent_folders = Map.get(folders, args.agent_id, [])
        updated = Map.put(folders, args.agent_id, [args.folder | agent_folders])
        {:ok, Map.put(ctx, :authorized_folders, updated)}

      {:when, :remove_authorized_folder} ->
        folders = Map.get(ctx, :authorized_folders, %{})
        agent_folders = Map.get(folders, args.agent_id, [])
        updated = Map.put(folders, args.agent_id, List.delete(agent_folders, args.folder))
        {:ok, Map.put(ctx, :authorized_folders, updated)}

      {:then, :assert_folder_access} ->
        last = Map.get(ctx, :last_folder_access)
        expected = String.to_atom(args.result)
        assert last == expected, "Expected folder access #{args.result}, got #{inspect(last)}"
        {:ok, ctx}

      # ---- tool interceptor ----
      {:given, :tool_interceptor_initialized} ->
        {:ok, ctx}

      {:given, :tool_pre_approved} ->
        approved = Map.get(ctx, :approved_tools, [])
        {:ok, Map.put(ctx, :approved_tools, [args.tool_name | approved])}

      {:when, :check_tool_approval} ->
        approved = Map.get(ctx, :approved_tools, [])
        result = ToolInterceptor.check(args.tool_name, %{}, %{approved_tools: approved})
        {:ok, Map.put(ctx, :last_interceptor_result, result)}

      {:then, :approval_required} ->
        result = Map.get(ctx, :last_interceptor_result)
        assert match?({:approval_required, _}, result),
               "Expected approval_required, got: #{inspect(result)}"
        {:ok, ctx}

      {:then, :approval_not_required} ->
        result = Map.get(ctx, :last_interceptor_result)
        assert result == :ok, "Expected :ok, got: #{inspect(result)}"
        {:ok, ctx}

      # ---- search settings ----
      {:given, :search_settings_clean} ->
        :persistent_term.erase({SearchSettings, :cached})
        if Application.get_env(:cortex, :env) == :test do
          Ecto.Adapters.SQL.Sandbox.checkout(Cortex.Repo)
          Ecto.Adapters.SQL.Sandbox.mode(Cortex.Repo, {:shared, self()})
        end
        Cortex.Repo.delete_all(SearchSettings)
        {:ok, ctx}

      {:when, :get_search_settings} ->
        settings = SearchSettings.get_settings()
        {:ok, Map.put(ctx, :search_settings, settings)}

      {:when, :update_search_provider} ->
        result = SearchSettings.update_settings(%{default_provider: args.provider})
        # 等待 SignalRecorder 将信号写入 history.jsonl
        Process.sleep(50)
        {:ok, Map.put(ctx, :last_update_result, result)}

      {:then, :search_provider_is} ->
        settings = Map.get(ctx, :search_settings) || SearchSettings.get_settings()
        assert settings.default_provider == args.provider,
               "Expected provider #{args.provider}, got #{settings.default_provider}"
        {:ok, ctx}

      {:then, :validation_error} ->
        result = Map.get(ctx, :last_update_result)
        assert match?({:error, %Ecto.Changeset{}}, result),
               "Expected validation error, got: #{inspect(result)}"
        {:ok, ctx}

      # ---- title generation ----
      {:given, :title_settings_clean} ->
        Settings.set_title_generation("disabled")
        {:ok, ctx}

      {:when, :get_title_mode} ->
        mode = Settings.get_title_generation()
        {:ok, Map.put(ctx, :title_mode, mode)}

      {:when, :set_title_mode} ->
        Settings.set_title_generation(args.mode)
        {:ok, Map.put(ctx, :title_mode, args.mode)}

      {:when, :trigger_title_generation} ->
        result = Cortex.Conversations.TitleGenerator.maybe_generate("test_conv", "Hello", nil)
        {:ok, Map.put(ctx, :title_gen_result, result)}

      {:then, :title_mode_is} ->
        mode = Map.get(ctx, :title_mode) || Settings.get_title_generation()
        assert mode == args.mode, "Expected title mode #{args.mode}, got #{mode}"
        {:ok, ctx}

      {:then, :title_generation_skipped} ->
        result = Map.get(ctx, :title_gen_result)
        assert result == :skip, "Expected :skip, got: #{inspect(result)}"
        {:ok, ctx}

      _ ->
        :no_match
    end
  end

  defp check_whitelist(ctx, args) do
    folders = Map.get(ctx, :authorized_folders, %{})
    agent_folders = Map.get(folders, args.agent_id, [])
    path = args.path

    if Enum.any?(agent_folders, &String.starts_with?(path, &1)) do
      :ok
    else
      :denied
    end
  end
end
