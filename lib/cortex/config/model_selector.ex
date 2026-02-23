defmodule Cortex.Config.ModelSelector do
  @moduledoc """
  Shared model selection helpers for channels and UI.
  """

  alias Cortex.Config.{Metadata, Settings}

  @doc """
  Returns {:ok, {model_name, model_id}} for the effective default model,
  or {:error, :no_available_models} when none are enabled.
  """
  def default_model_info do
    available = Metadata.get_available_models()

    if available == [] do
      {:error, :no_available_models}
    else
      effective = Settings.get_effective_skill_default_model()
      model = Enum.find(available, &(&1.name == effective)) || List.first(available)
      model_name = model.name
      model_id = model.id
      {:ok, {model_name, model_id}}
    end
  end

  @doc """
  Resolve model from a stored model_config, falling back to defaults.
  Returns {:ok, {model_name, model_id}} or {:error, :no_available_models}.
  """
  def resolve_model_from_config(model_config, default_model_name, default_model_id) do
    available = Metadata.get_available_models()
    model_id = model_id_from_config(model_config || %{})
    model = if model_id, do: Enum.find(available, &(&1.id == model_id)), else: nil

    cond do
      model ->
        {:ok, {model.name, model.id}}

      default_model_id ->
        {:ok, {default_model_name, default_model_id}}

      available != [] ->
        first = List.first(available)
        {:ok, {first.name, first.id}}

      true ->
        {:error, :no_available_models}
    end
  end

  def model_id_from_config(model_config) when is_map(model_config) do
    model_config[:model_id] || model_config["model_id"]
  end

  def model_config_from_id(nil), do: %{}
  def model_config_from_id(model_id), do: %{model_id: model_id}
end
