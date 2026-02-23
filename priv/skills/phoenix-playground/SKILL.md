---
name: phoenix-playground
description: Build professional, full-stack Phoenix LiveView prototypes in a single file. Ideal for temporary page demos, interactive feature archival, and standalone UI documentation.
---

# Phoenix Playground Skill

This skill enables you to build standalone, professional-grade web prototypes in a single Elixir file. Beyond prototyping, it serves as a powerful medium for **temporary page demonstrations** and **interactive feature archival**.

## 1. Key Use Cases

- **Temporary Page Demos**: Quickly spin up a UI to show a concept to a user without cluttering the main app.
- **Interactive Archival**: Save a specific bug reproduction or feature experiment as a single, runnable `.exs` file.
- **Standalone Documentation**: Create "living" documentation where logic can be tested and visualized interactively.
- **Creative One-offs**: Quickly generate personal or one-time web pages like birthday greetings, event countdowns, or holiday cards.
- **One-off Internal Tools**: Build a quick dashboard for data migration or system monitoring that doesn't need to be part of the core product.

## 2. Creative One-off Template (e.g., Greeting Page)

For non-functional, purely visual pages, focus on Tailwind's animation and design classes.

```elixir
defmodule GreetingPage do
  use Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <script src="https://cdn.tailwindcss.com"></script>
    <div class="min-h-screen bg-gradient-to-br from-pink-100 to-indigo-200 flex items-center justify-center p-4">
      <div class="bg-white rounded-3xl shadow-2xl p-12 text-center transform hover:scale-105 transition-all duration-500">
        <div class="text-6xl mb-6">🎂</div>
        <h1 class="text-5xl font-black text-transparent bg-clip-text bg-gradient-to-r from-purple-600 to-pink-600 animate-pulse">
          Happy Birthday!
        </h1>
        <p class="mt-6 text-slate-600 text-lg">Wishing you a day filled with joy and laughter.</p>
        <div class="mt-8 flex justify-center gap-2">
          <span :for={_ <- 1..5} class="animate-bounce">🎈</span>
        </div>
      </div>
    </div>
    """
  end
end
PhoenixPlayground.start(live: GreetingPage, port: 4006)
```

## 3. Professional Configuration

Use `Mix.install/2` to lock in UI, networking, and utility libraries.

```elixir
Mix.install([
  {:phoenix_playground, "~> 0.1.8"},
  {:jason, "~> 1.4"},
  {:req, "~> 0.5"}
])
```

## 2. Advanced Routing & Controllers

Instead of a single LiveView, you can define a full `Router` for complex applications.

```elixir
defmodule MyRouter do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_root_layout, html: {PhoenixPlayground.Layout, :root}
    plug :put_secure_browser_headers
  end

  scope "/" do
    pipe_through :browser
    live "/", MyHomeLive
    # live "/settings", MySettingsLive
  end
end

# Start using the Router
PhoenixPlayground.start(plug: MyRouter, port: 4005)
```

## 3. Real-Time Collaboration (PubSub)

Use the built-in `PhoenixPlayground.PubSub` to broadcast updates across all connected clients.

```elixir
defmodule MyLive do
  use Phoenix.LiveView
  @topic "global_events"

  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(PhoenixPlayground.PubSub, @topic)
    {:ok, stream(socket, :messages, [])}
  end

  def handle_event("send", %{"msg" => msg}, socket) do
    Phoenix.PubSub.broadcast(PhoenixPlayground.PubSub, @topic, {:new_msg, msg})
    {:noreply, socket}
  end

  def handle_info({:new_msg, msg}, socket) do
    {:noreply, stream_insert(socket, :messages, %{id: System.unique_integer(), text: msg})}
  end
end
```

## 4. JavaScript Hooks & Tailwind Styling

Inject custom JS logic and Tailwind CSS directly into your `render/1` function.

```elixir
def render(assigns) do
  ~H"""
  <script src="https://cdn.tailwindcss.com"></script>
  <div phx-hook="AutoScroll" id="chat-container" class="p-10 bg-slate-100 min-h-screen">
    <h1 class="text-3xl font-bold text-indigo-600">Live Chat</h1>
    <!-- UI Elements -->
  </div>

  <script>
    window.hooks = window.hooks || {};
    window.hooks.AutoScroll = {
      updated() { this.el.scrollTop = this.el.scrollHeight; }
    };
  </script>
  """
end
```

## 5. Built-in Testing (ExUnit)

You can write and run tests for your prototype within the same file.

```elixir
# At the bottom of your .exs script:
ExUnit.start()

defmodule MyLiveTest do
  use ExUnit.Case
  use PhoenixPlayground.Test, live: MyHomeLive

  test "it increments count" do
    {:ok, view, _html} = live(build_conn(), "/")
    assert render_click(view, :inc) =~ "Count: 1"
  end
end
```

## 6. Execution & Safety

### 公共访问（把 Playground 对其它设备 / 网络公开） 🔓

如果你想让同一局域网或互联网中的其他设备访问 Playground，需要将监听地址设置为 0.0.0.0：

```elixir
PhoenixPlayground.start(
  plug: PlaygroundRouter,
  port: 5005,
  ip: {0, 0, 0, 0},
  endpoint_options: [secret_key_base: PlaygroundConfig.secret_key_base!()]
)
```

要点说明：
- `ip: {0, 0, 0, 0}` 会让服务绑定到所有网络接口，从而允许局域网或公网（如果路由/防火墙允许）访问。✅
- **必须**提供有效的 `secret_key_base`（可通过 `endpoint_options` 传入或在环境变量中设置），否则会出现会话/签名错误。🔑

安全与部署建议 ⚠️

- 优先在受控网络（公司/家庭局域网）内使用；仅在必要时才在公网暴露端口。💡
- 在主机或云层启用防火墙规则，只允许受信任来源访问该端口。
- 使用反向代理（nginx/Caddy）在前端处理 TLS 与认证；不要直接在 Playground 上暴露敏感 API。🔐
- 临时演示推荐使用 SSH 隧道 或 ngrok/cloudflared 等工具，避免长期在公网开放端口：
  - SSH 隧道示例： `ssh -L 5005:localhost:5005 user@remote-host`
- 对包含真实/敏感数据的逻辑不要在 Playground 中运行。

快速检查清单 ✅
1. 端口未被占用且已正确设置
2. 已配置 `secret_key_base`
3. 防火墙/路由器只允许受信任网络访问
4. 如需公网访问，优先使用隧道或反向代理并启用 TLS

从另一台机器访问（示例）

- 启动：`elixir greeting_page.exs`（或上面示例的端口 5005）
- 在同一局域网的另一台机器上访问： `curl http://<host-ip>:5005/` 或在浏览器打开 `http://<host-ip>:5005/`

- **Run**: `elixir my_fullstack_app.exs`
- **Port**: Always check for port conflicts. Default to `4005-4100`.
- **Termination**: Use `ctrl+c` to stop the server. In scripts, ensure `ExUnit` runs after the app logic or in a separate flow.