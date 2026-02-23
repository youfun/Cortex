defmodule CortexWeb.PageControllerTest do
  use CortexWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ "Cortex"
    assert html =~ "Chat"
  end
end
