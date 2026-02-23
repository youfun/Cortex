defmodule Cortex.Channel.Adapter do
  @moduledoc """
  Channel adapter behavior for inbound/outbound SNS integrations.
  """

  @callback channel() :: String.t()
  @callback enabled?() :: boolean()
  @callback child_specs() :: [Supervisor.child_spec() | {module(), term()}]
  @callback config() :: keyword()

  @optional_callbacks config: 0
end
