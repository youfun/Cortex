defmodule CortexWeb.PageController do
  use CortexWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
