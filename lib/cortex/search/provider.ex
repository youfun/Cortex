defmodule Cortex.Search.Provider do
  @moduledoc """
  Behaviour for web search providers (Brave, Tavily, etc.).
  """

  @type result :: %{
          title: String.t(),
          url: String.t(),
          snippet: String.t(),
          published_date: String.t() | nil
        }

  @callback search(query :: String.t(), opts :: keyword()) ::
              {:ok, [result()]} | {:error, term()}

  @callback name() :: String.t()

  @callback available?() :: boolean()
end
