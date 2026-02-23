defmodule Cortex.Permissions do
  @moduledoc """
  Permissions context.

  This module is currently used by test fixtures. Permission decisions in the
  runtime are primarily handled via signals and agent permission flow.
  """

  @doc """
  Creates a permission request.

  Currently returns an in-memory map with a generated `:id` to satisfy
  fixture usage. No persistence is performed.
  """
  def create_permission_request(attrs) when is_map(attrs) do
    {:ok,
     attrs
     |> Map.new()
     |> Map.put_new(:id, Ecto.UUID.generate())}
  end

  def create_permission_request(attrs) when is_list(attrs) do
    attrs
    |> Enum.into(%{})
    |> create_permission_request()
  end
end
