defmodule CortexWeb.FeishuWebhookControllerTest do
  use CortexWeb.ConnCase

  test "fails without verification token (secure behavior)", %{conn: conn} do
    # Ensure no token is configured
    Application.put_env(:cortex, :feishu, [])

    conn =
      post(conn, ~p"/api/feishu/webhook", %{
        "type" => "url_verification",
        "challenge" => "test_challenge",
        "token" => "random_token"
      })

    assert response(conn, 401) == "invalid token"
  end

  test "fails with incorrect verification token", %{conn: conn} do
    # Configure a token
    Application.put_env(:cortex, :feishu, verification_token: "secret_token")

    conn =
      post(conn, ~p"/api/feishu/webhook", %{
        "type" => "url_verification",
        "challenge" => "test_challenge",
        "token" => "wrong_token"
      })

    assert response(conn, 401) == "invalid token"
  end

  test "succeeds with correct verification token", %{conn: conn} do
    # Configure a token
    Application.put_env(:cortex, :feishu, verification_token: "secret_token")

    conn =
      post(conn, ~p"/api/feishu/webhook", %{
        "type" => "url_verification",
        "challenge" => "test_challenge",
        "token" => "secret_token"
      })

    assert json_response(conn, 200) == %{"challenge" => "test_challenge"}
  end
end
