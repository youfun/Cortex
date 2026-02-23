defmodule Cortex.Config do
  @moduledoc """
  The Config context.
  """

  import Ecto.Query, warn: false
  alias Cortex.Repo
  alias Cortex.Config.LlmModel

  @doc """
  Returns the list of llm_models.
  """
  def list_llm_models do
    Repo.all(LlmModel)
  end

  @doc """
  Gets a single llm_model.
  """
  def get_llm_model!(id), do: Repo.get!(LlmModel, id)

  @doc """
  Gets a single llm_model by name.
  """
  def get_llm_model_by_name(name) when is_binary(name) do
    Repo.get_by(LlmModel, name: name)
  end

  @doc """
  Creates a llm_model.
  """
  def create_llm_model(attrs) do
    %LlmModel{}
    |> LlmModel.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a llm_model.
  """
  def update_llm_model(%LlmModel{} = llm_model, attrs) do
    llm_model
    |> LlmModel.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a llm_model.
  """
  def delete_llm_model(%LlmModel{} = llm_model) do
    Repo.delete(llm_model)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking llm_model changes.
  """
  def change_llm_model(%LlmModel{} = llm_model, attrs \\ %{}) do
    LlmModel.changeset(llm_model, attrs)
  end
end
