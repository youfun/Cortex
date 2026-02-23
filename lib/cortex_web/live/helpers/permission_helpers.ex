defmodule CortexWeb.PermissionHelpers do
  @moduledoc """
  Permission request queue management extracted from JidoLive.
  """

  import Phoenix.Component, only: [assign: 2]

  alias CortexWeb.AgentLiveHelpers

  def enqueue(socket, request) do
    already_in_queue =
      Enum.any?(socket.assigns.permission_queue, &(&1.request_id == request.request_id))

    is_current =
      socket.assigns.pending_permission_request &&
        socket.assigns.pending_permission_request.request_id == request.request_id

    if already_in_queue or is_current do
      socket
    else
      new_queue = append_one(socket.assigns.permission_queue, request)
      process_queue(assign(socket, permission_queue: new_queue))
    end
  end

  def consume_queue(socket) do
    process_queue(assign(socket, pending_permission_request: nil, show_permission_modal: false))
  end

  def resolve(socket, request_id, decision) do
    AgentLiveHelpers.emit_permission_resolve(socket, request_id, decision)
    consume_queue(socket)
  end

  def parse_decision(decision) when is_binary(decision) do
    case String.downcase(decision) do
      "allow" -> :allow
      "allow_always" -> :allow_always
      "deny" -> :deny
      _ -> :deny
    end
  end

  def parse_decision(_decision), do: :deny

  defp process_queue(socket) do
    if socket.assigns.show_permission_modal do
      socket
    else
      case socket.assigns.permission_queue do
        [] ->
          assign(socket, show_permission_modal: false, pending_permission_request: nil)

        [next_req | rest] ->
          assign(socket,
            permission_queue: rest,
            pending_permission_request: next_req,
            show_permission_modal: true,
            is_thinking: false
          )
      end
    end
  end

  defp append_one(list, item) do
    list
    |> Enum.reverse()
    |> then(&[item | &1])
    |> Enum.reverse()
  end
end
