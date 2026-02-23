defmodule Cortex.Agents.PermissionFlow do
  @moduledoc """
  Tracks pending tool calls that require user permission.
  """

  def track_pending(pending_map, call_id, call_data) do
    Map.put(pending_map, call_id, call_data)
  end

  def resolve(pending_map, request_id) do
    case find_by_req_id(pending_map, request_id) do
      {call_id, call_data} -> {:ok, call_id, call_data}
      nil -> :error
    end
  end

  def find_by_req_id(pending_map, req_id) do
    Enum.find(pending_map, fn {_, data} -> data.req_id == req_id end)
  end
end
