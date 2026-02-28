defmodule CortexWeb.Router do
  use CortexWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CortexWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_admin do
    plug :check_auth
  end

  scope "/", CortexWeb do
    pipe_through [:browser, :require_admin]

    live_session :admin, on_mount: [], layout: {CortexWeb.Layouts, :app} do
      live "/", JidoLive, :index

      # Memory System
      live "/memory", MemoryLive.Index, :overview

      # Settings (with secondary sidebar)
      live "/settings", SettingsLive.Index, :channels
      live "/settings/channels", SettingsLive.Index, :channels
      live "/settings/models", SettingsLive.Index, :models
      live "/settings/models/new", SettingsLive.Index, :new_model
      live "/settings/models/:id/edit", SettingsLive.Index, :edit_model
      live "/settings/search", SettingsLive.Index, :search
    end
  end

  # System API
  scope "/api/system", CortexWeb do
    pipe_through :api
    get "/health", SystemController, :health
    post "/shutdown", SystemController, :shutdown
  end

  # Feishu Webhook
  scope "/api/feishu", CortexWeb do
    pipe_through :api
    post "/webhook", FeishuWebhookController, :webhook
  end

  def check_auth(conn, _opts) do
    # 跳过认证的条件:
    # 1. 开发环境 (MIX_ENV=dev)
    # 2. GUI 桌面模式 (DESKTOP_MODE=true)
    # 只有在生产环境的 server 部署时才需要认证
    cond do
      Application.get_env(:cortex, :env) == :dev ->
        # 开发环境直接放行
        conn

      System.get_env("DESKTOP_MODE") == "true" ->
        # GUI 桌面版本直接放行
        conn

      true ->
        # 生产环境 server 部署需要认证
        with {user, pass} <- Plug.BasicAuth.parse_basic_auth(conn),
             true <- user == System.get_env("AUTH_USER", "admin"),
             true <- pass == System.get_env("AUTH_PASS", "admin") do
          conn
        else
          _ ->
            conn
            |> Plug.BasicAuth.request_basic_auth()
            |> halt()
        end
    end
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:cortex, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CortexWeb.Telemetry
    end
  end
end
