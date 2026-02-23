Mix.install([
  {:ex_creem, path: "."},
  {:phoenix_playground, "~> 0.1.8"},
  {:jason, "~> 1.4"}
])

defmodule CreemTestLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       api_key: "",
       product_id: "",
       test_mode: true,
       checkout_url: nil,
       error: nil,
       loading: false,
       logs: []
     )}
  end

  def render(assigns) do
    ~H"""
    <script src="https://cdn.tailwindcss.com"></script>
    <div class="min-h-screen bg-gray-100 py-12 px-4 sm:px-6 lg:px-8">
      <div class="max-w-md mx-auto bg-white rounded-xl shadow-md overflow-hidden md:max-w-2xl p-8">
        <div class="text-center mb-8">
          <h1 class="text-3xl font-extrabold text-gray-900">ExCreem Payment Test</h1>
          <p class="mt-2 text-sm text-gray-600">Enter your credentials to test the checkout flow</p>
        </div>

        <form phx-change="validate" phx-submit="create_checkout" class="space-y-6">
          <div>
            <label for="api_key" class="block text-sm font-medium text-gray-700">Creem API Key</label>
            <div class="mt-1">
              <input type="password" name="api_key" id="api_key" value={@api_key}
                class="block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                placeholder="creem_..." required />
            </div>
          </div>

          <div>
            <label for="product_id" class="block text-sm font-medium text-gray-700">Product ID</label>
            <div class="mt-1">
              <input type="text" name="product_id" id="product_id" value={@product_id}
                class="block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                placeholder="prod_..." required />
            </div>
          </div>

          <div class="flex items-center">
            <input id="test_mode" name="test_mode" type="checkbox" checked={@test_mode}
              class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded" />
            <label for="test_mode" class="ml-2 block text-sm text-gray-900">
              Enable Test Mode
            </label>
          </div>

          <div>
            <button type="submit" disabled={@loading}
              class={"w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white " <> (if @loading, do: "bg-indigo-400 cursor-not-allowed", else: "bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500")}>
              <%= if @loading, do: "Processing...", else: "Generate Checkout URL" %>
            </button>
          </div>
        </form>

        <%= if @checkout_url do %>
          <div class="mt-8 p-4 bg-green-50 border border-green-200 rounded-lg">
            <h3 class="text-lg font-medium text-green-800">Checkout Link Ready!</h3>
            <div class="mt-2 text-sm text-green-700">
              <a href={@checkout_url} target="_blank" class="font-bold underline break-all hover:text-green-900">
                {@checkout_url}
              </a>
            </div>
            <p class="mt-2 text-xs text-green-600 italic">Click the link above to proceed to the payment page.</p>
          </div>
        <% end %>

        <%= if @error do %>
          <div class="mt-8 p-4 bg-red-50 border border-red-200 rounded-lg text-red-700">
            <h3 class="text-lg font-medium">Error</h3>
            <pre class="mt-2 text-sm overflow-auto max-h-40 whitespace-pre-wrap">{@error}</pre>
          </div>
        <% end %>

        <div class="mt-10 border-t border-gray-200 pt-6">
          <h3 class="text-sm font-semibold text-gray-500 uppercase tracking-wider">Activity Log</h3>
          <div class="mt-4 bg-gray-900 rounded-lg p-4 font-mono text-xs text-green-400 h-40 overflow-y-auto">
            <%= for log <- Enum.reverse(@logs) do %>
              <div class="mb-1">
                <span class="text-gray-500">[<%= Calendar.strftime(log.time, "%H:%M:%S") %>]</span>
                {log.msg}
              </div>
            <% end %>
            <%= if Enum.empty?(@logs) do %>
              <div class="text-gray-600">No activity yet...</div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("validate", params, socket) do
    test_mode = Map.get(params, "test_mode") == "on"
    api_key = Map.get(params, "api_key")
    product_id = Map.get(params, "product_id")

    {:noreply, assign(socket, api_key: api_key, product_id: product_id, test_mode: test_mode)}
  end

  def handle_event("create_checkout", _params, socket) do
    socket =
      socket
      |> assign(loading: true, error: nil, checkout_url: nil)
      |> add_log("Starting checkout creation for product: #{socket.assigns.product_id}")

    # Creem API appears to use snake_case in Elixir
    params = %{
      "product_id" => socket.assigns.product_id,
      "success_url" => "http://localhost:4000/success"
    }

    opts = [
      api_key: socket.assigns.api_key,
      test_mode: socket.assigns.test_mode
    ]

    case ExCreem.Resources.Checkout.create(params, opts) do
      {:ok, session} ->
        url = session["checkout_url"]

        {:noreply,
         socket
         |> assign(checkout_url: url, loading: false)
         |> add_log("Successfully created checkout URL.")}

      {:error, {status, body}} ->
        error_msg = Jason.encode!(body, pretty: true)

        {:noreply,
         socket
         |> assign(error: "HTTP #{status}\n#{error_msg}", loading: false)
         |> add_log("Failed with status #{status}")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(error: inspect(reason), loading: false)
         |> add_log("Failed to create checkout.")}
    end
  end

  defp add_log(socket, msg) do
    update(socket, :logs, fn logs -> [%{msg: msg, time: DateTime.utc_now()} | logs] end)
  end
end

defmodule SuccessLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <script src="https://cdn.tailwindcss.com"></script>
    <div class="min-h-screen bg-green-50 flex flex-col justify-center py-12 sm:px-6 lg:px-8">
      <div class="mt-8 sm:mx-auto sm:w-full sm:max-w-md">
        <div class="bg-white py-8 px-4 shadow sm:rounded-lg sm:px-10 text-center">
          <div class="mx-auto flex items-center justify-center h-12 w-12 rounded-full bg-green-100 mb-4">
            <svg class="h-6 w-6 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
            </svg>
          </div>
          <h2 class="text-3xl font-extrabold text-gray-900 mb-2">Payment Successful!</h2>
          <p class="text-sm text-gray-500 mb-6">Thank you for your purchase.</p>
          <a href="/" class="font-medium text-indigo-600 hover:text-indigo-500">
            Return to Test Page
          </a>
        </div>
      </div>
    </div>
    """
  end
end

defmodule CreemTestRouter do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:put_root_layout, html: {PhoenixPlayground.Layout, :root})
    plug(:put_secure_browser_headers)
  end

  scope "/" do
    pipe_through(:browser)

    live("/", CreemTestLive)
    live("/success", SuccessLive)
  end
end

PhoenixPlayground.start(plug: CreemTestRouter, port: 4000)
