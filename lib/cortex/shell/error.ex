defmodule Cortex.Shell.Error do
  @moduledoc """
  Minimal shell error struct to replace the `jido_shell` dependency.
  """

  defexception [:code, :message, context: %{}]

  @type t :: %__MODULE__{code: {atom(), atom()}, message: String.t(), context: map()}

  def shell(code, ctx \\ %{}) do
    %__MODULE__{code: {:shell, code}, message: to_string(code), context: ctx}
  end

  def command(code, ctx \\ %{}) do
    %__MODULE__{code: {:command, code}, message: to_string(code), context: ctx}
  end
end
