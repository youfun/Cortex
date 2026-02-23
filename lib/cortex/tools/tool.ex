defmodule Cortex.Tools.Tool do
  @moduledoc """
  Standard tool definition stored in the registry.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          parameters: keyword(),
          module: module()
        }

  defstruct [:name, :description, :parameters, :module]
end

defmodule Cortex.Tools.ToolBehaviour do
  @moduledoc """
  Behaviour required for all tool handler modules.
  """

  @callback execute(args :: map(), ctx :: map()) ::
              {:ok, term()}
              | {:error, term()}
              | {:error, {:permission_denied, binary()}}
end
