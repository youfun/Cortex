defmodule Cortex.LLM.LLMDB do
  @moduledoc """
  模型元数据同步中心

  支持从自定义 Base URL (兼容 OpenAI 格式) 或本地集成库 `llm_db` 获取模型信息。
  """

  require Logger
  alias Cortex.Config.Metadata

  @default_timeout 10_000

  @doc """
  同步指定驱动的模型到数据库
  """
  def sync_drive(drive_id) when is_binary(drive_id) do
    alias Cortex.Config

    {adapter, base_url} = resolve_drive_adapter_base_url(drive_id, Config)

    drive_id
    |> fetch_models_for_drive(adapter, base_url)
    |> persist_models_sync(drive_id)
  end

  defp resolve_drive_adapter_base_url(drive_id, config_mod) do
    drive_config = Enum.find(Metadata.list_standard_drives(), &(&1.id == drive_id))
    model = config_mod.get_llm_model_by_name(drive_id)

    adapter =
      (model && model.adapter) ||
        (drive_config && drive_config.adapter) ||
        drive_id

    base_url = (model && model.base_url) || ""
    {adapter, base_url}
  end

  defp fetch_models_for_drive(_drive_id, adapter, ""), do: fetch_local_models(adapter)

  defp fetch_models_for_drive(drive_id, adapter, base_url) when is_binary(base_url) do
    case fetch_from_base_url(base_url, drive_id, adapter) do
      {:ok, models} when is_list(models) and models != [] ->
        {:ok, models}

      {:ok, _} ->
        Logger.warning(
          "Custom base_url for #{drive_id} returned empty models, falling back to local LLMDB"
        )

        fetch_local_models(adapter)

      {:error, reason} ->
        Logger.warning(
          "Failed to fetch models from base_url for #{drive_id}: #{inspect(reason)}. Falling back to local LLMDB"
        )

        fetch_local_models(adapter)
    end
  end

  defp persist_models_sync({:ok, models}, drive_id) when is_list(models) do
    Metadata.sync_from_llmdb(drive_id, models)
    {:ok, length(models)}
  end

  defp persist_models_sync(error, _drive_id), do: error

  @doc """
  从指定的 Base URL 获取模型列表 (OpenAI/OpenRouter 兼容格式)
  """
  def fetch_from_base_url(base_url, provider_drive, adapter \\ "openai") do
    url =
      base_url
      |> String.trim_trailing("/")
      |> then(fn u ->
        if String.ends_with?(u, "/models"), do: u, else: "#{u}/models"
      end)

    Logger.info("Fetching models from custom base_url: #{url}")

    case Req.get(url, receive_timeout: @default_timeout) do
      {:ok, %{status: 200, body: body}} ->
        models =
          case body do
            %{"data" => data} when is_list(data) ->
              parse_openai_models(data, provider_drive, adapter)

            data when is_list(data) ->
              parse_openai_models(data, provider_drive, adapter)

            _ ->
              []
          end

        {:ok, models}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  从本地 llm_db 库获取模型数据
  """
  def fetch_local_models(adapter_name) do
    adapter_atom = to_adapter_atom(adapter_name)

    case Code.ensure_loaded?(LLMDB) do
      true ->
        adapter_atom
        |> Elixir.LLMDB.models()
        |> Enum.filter(fn model ->
          filter_recent_models(model) and
            Elixir.LLMDB.allowed?({adapter_atom, model.id}) and
            !global_denied?(model.id)
        end)
        |> Enum.map(fn m -> convert_library_model(m, Atom.to_string(adapter_atom)) end)
        |> then(&{:ok, &1})

      false ->
        {:ok, []}
    end
  end

  # 全局排除规则
  defp global_denied?(model_id) when is_binary(model_id) do
    id = String.downcase(model_id)

    cond do
      String.contains?(id, "o4-mini-2025") -> true
      String.contains?(id, "o4-mini-deep-research") -> true
      String.contains?(id, "omni-moderation") -> true
      String.contains?(id, "sora-") -> true
      true -> false
    end
  end

  defp global_denied?(_), do: false

  defp filter_recent_models(model) do
    case get_release_date(model) do
      nil ->
        true

      %Date{} = release_date ->
        Date.compare(release_date, ~D[2025-01-01]) != :lt
    end
  end

  defp get_release_date(%{release_date: date_string}) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp get_release_date(%{extra: %{release_date: date_string}}) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp get_release_date(_), do: nil

  defp to_adapter_atom(name) when is_atom(name), do: name

  defp to_adapter_atom(name) when is_binary(name) do
    case Cortex.Utils.SafeAtom.to_existing(name) do
      {:ok, atom} -> atom
      {:error, :not_found} -> :unknown
    end
  end

  @doc """
  同步所有标准驱动
  """
  def sync_all_drives do
    drives = Metadata.list_standard_drives()

    results =
      Enum.map(drives, fn drive ->
        case sync_drive(drive.id) do
          {:ok, count} ->
            Logger.info("Synced #{count} models for drive #{drive.id}")
            {drive.id, :ok, count}

          {:error, reason} ->
            Logger.warning("Failed to sync drive #{drive.id}: #{inspect(reason)}")
            {drive.id, :error, reason}
        end
      end)

    success_count = Enum.count(results, fn {_, status, _} -> status == :ok end)

    total_models =
      results
      |> Enum.filter(fn {_, status, _} -> status == :ok end)
      |> Enum.map(fn {_, _, count} -> count end)
      |> Enum.sum()

    {:ok,
     %{
       drives: length(drives),
       synced: success_count,
       total_models: total_models,
       results: results
     }}
  end

  # 将 llm_db 库的 %LLMDB.Model{} 转换为内部 Schema 兼容格式
  defp convert_library_model(m, adapter) do
    limits = m.limits || %{}
    cost = m.cost || %{}

    %{
      "name" => m.id,
      "display_name" => m.name,
      "provider_drive" => adapter,
      "adapter" => adapter,
      "source" => "llmdb",
      "status" => if(m.deprecated, do: "deprecated", else: "active"),
      "context_window" => limits[:context] || 4096,
      "capabilities" => convert_capabilities(m.capabilities),
      "pricing" =>
        %{"input" => cost[:input], "output" => cost[:output]}
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new(),
      "architecture" => %{"input_modalities" => ["text"], "output_modalities" => ["text"]},
      "enabled" => false
    }
  end

  defp convert_capabilities(nil) do
    %{
      "vision" => false,
      "function_calling" => false,
      "streaming" => true,
      "json_mode" => false,
      "reasoning" => false,
      "computer_use" => false
    }
  end

  defp convert_capabilities(cap) do
    %{
      "vision" => cap[:vision] || false,
      "function_calling" => get_in(cap, [:tools, :enabled]) || false,
      "streaming" => true,
      "json_mode" => get_in(cap, [:json, :native]) || false,
      "reasoning" => get_in(cap, [:reasoning, :enabled]) || cap[:reasoning] == true,
      "computer_use" => cap[:computer_use] || false
    }
  end

  # 解析 OpenAI 格式的模型数据
  defp parse_openai_models(data, provider_drive, adapter) do
    adapter_atom = to_adapter_atom(adapter)

    data
    |> Enum.map(fn raw ->
      model_id = raw["id"] || raw["name"]

      %{
        "name" => model_id,
        "display_name" => raw["display_name"] || model_id,
        "provider_drive" => provider_drive,
        "adapter" => adapter,
        "source" => "remote_api",
        "status" => "active",
        "context_window" => raw["context_window"] || raw["context_length"] || 4096,
        "capabilities" => %{
          "vision" => !!raw["capabilities"]["vision"],
          "function_calling" => !!raw["capabilities"]["function_calling"],
          "streaming" => true,
          "json_mode" => !!raw["capabilities"]["json_mode"],
          "reasoning" => !!raw["capabilities"]["reasoning"],
          "computer_use" => false
        },
        "pricing" => %{},
        "architecture" => %{},
        "enabled" => false
      }
    end)
    |> Enum.filter(fn m ->
      case Code.ensure_loaded?(LLMDB) do
        true -> Elixir.LLMDB.allowed?({adapter_atom, m["name"]}) and !global_denied?(m["name"])
        false -> !global_denied?(m["name"])
      end
    end)
  end
end
