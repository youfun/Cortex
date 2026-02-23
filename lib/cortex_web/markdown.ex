defmodule CortexWeb.Markdown do
  @moduledoc """
  Markdown rendering helper using Earmark.
  """

  @doc """
  Renders markdown string to safe HTML.
  """
  def to_html(nil), do: ""
  def to_html(""), do: ""

  def to_html(markdown) when is_binary(markdown) do
    case Earmark.as_html(markdown) do
      {:ok, html, _messages} ->
        html

      {:error, html, _messages} ->
        # Earmark still returns partial HTML on error
        html
    end
  end

  @doc """
  Renders markdown to Phoenix.HTML.safe.
  """
  def to_safe_html(markdown) do
    markdown
    |> to_html()
    |> Phoenix.HTML.raw()
  end
end
