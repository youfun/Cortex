defmodule Cortex.Channels.Feishu.Supervisor do
  @moduledoc """
  Feishu 通道管理树。
  """
  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    cfg = Application.get_env(:cortex, :feishu, [])
    app_id = cfg[:app_id]
    app_secret = cfg[:app_secret]

    children =
      if present?(app_id) and present?(app_secret) do
        [
          Cortex.Channels.Feishu.Receiver,
          Cortex.Channels.Feishu.Dispatcher
        ]
      else
        []
      end

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp present?(value) when is_binary(value), do: value != ""
  defp present?(value), do: not is_nil(value)
end
