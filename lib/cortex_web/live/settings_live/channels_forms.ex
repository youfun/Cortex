defmodule CortexWeb.SettingsLive.ChannelsForms do
  use CortexWeb, :html

  alias Cortex.Channels

  def parse_tab(tab) when is_binary(tab) do
    case tab do
      "telegram" -> :telegram
      "feishu" -> :feishu
      _ -> :telegram
    end
  end

  def parse_tab(_), do: :telegram

  def save_channel_config(params, socket, reload_configs) when is_function(reload_configs, 1) do
    %{"adapter" => adapter} = params
    enabled = Map.has_key?(params, "enabled")

    config_params =
      adapter
      |> config_params_for_adapter(params)
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new()

    case Channels.get_channel_config_by_adapter(adapter) do
      nil ->
        Channels.create_channel_config(%{
          "adapter" => adapter,
          "name" => "#{String.capitalize(adapter)} Bot",
          "config" => config_params,
          "enabled" => enabled
        })

      existing ->
        Channels.update_channel_config(existing, %{
          "config" => config_params,
          "enabled" => enabled
        })
    end

    socket
    |> Phoenix.LiveView.put_flash(:info, "#{String.capitalize(adapter)} configuration saved.")
    |> reload_configs.()
  end

  # --- Forms ---

  def dingtalk_form(assigns) do
    assigns =
      assigns
      |> assign_form_config("dingtalk")
      |> assign_new(:target, fn -> nil end)

    ~H"""
    <form phx-submit="save" phx-target={@target} class="space-y-6">
      <input type="hidden" name="adapter" value="dingtalk" />

      <.toggle_enabled enabled={@enabled} label="Enable DingTalk Channel" />

      <h3 class="text-lg font-semibold text-slate-200 pt-2">Credentials</h3>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <.input_group name="client_id" label="AppKey (Client ID)" value={@config["client_id"]} />
        <.input_group
          name="client_secret"
          label="AppSecret (Client Secret)"
          value={@config["client_secret"]}
          type="password"
        />
      </div>

      <h3 class="text-lg font-semibold text-slate-200 pt-4">Policies</h3>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <.select_group
          name="dm_policy"
          label="DM Policy"
          value={@config["dm_policy"]}
          options={["open", "pairing", "allowlist"]}
        />
        <.select_group
          name="group_policy"
          label="Group Policy"
          value={@config["group_policy"]}
          options={["open", "allowlist", "disabled"]}
        />
      </div>

      <div class="flex items-center space-x-3 pt-4">
        <input
          type="checkbox"
          name="enable_ai_card"
          id="dingtalk_ai_card"
          checked={@config["enable_ai_card"] == true}
          class="rounded border-slate-600 bg-slate-800 text-teal-600 focus:ring-teal-500 focus:ring-offset-slate-900"
        />
        <label for="dingtalk_ai_card" class="text-sm font-medium text-slate-300">
          Enable AI Card (Stream Mode)
        </label>
      </div>

      <.save_button />
    </form>
    """
  end

  def feishu_form(assigns) do
    assigns =
      assigns
      |> assign_form_config("feishu")
      |> assign_new(:target, fn -> nil end)

    ~H"""
    <form phx-submit="save" phx-target={@target} class="space-y-6">
      <input type="hidden" name="adapter" value="feishu" />

      <.toggle_enabled enabled={@enabled} label="Enable Feishu Channel" />

      <h3 class="text-lg font-semibold text-slate-200 pt-2">App Credentials</h3>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <.input_group name="app_id" label="App ID" value={@config["app_id"]} />
        <.input_group
          name="app_secret"
          label="App Secret"
          value={@config["app_secret"]}
          type="password"
        />
      </div>

      <h3 class="text-lg font-semibold text-slate-200 pt-4">Event Subscription</h3>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <.input_group
          name="encrypt_key"
          label="Encrypt Key"
          value={@config["encrypt_key"]}
          type="password"
        />
        <.input_group
          name="verification_token"
          label="Verification Token"
          value={@config["verification_token"]}
        />
      </div>

      <div>
        <.select_group
          name="mode"
          label="Connection Mode"
          value={@config["mode"]}
          options={["websocket", "webhook"]}
        />
      </div>

      <.save_button />
    </form>
    """
  end

  def wecom_form(assigns) do
    assigns =
      assigns
      |> assign_form_config("wecom")
      |> assign_new(:target, fn -> nil end)

    ~H"""
    <form phx-submit="save" phx-target={@target} class="space-y-6">
      <input type="hidden" name="adapter" value="wecom" />

      <.toggle_enabled enabled={@enabled} label="Enable WeCom App" />

      <h3 class="text-lg font-semibold text-slate-200 pt-2">Receiver (Callback)</h3>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <.input_group name="token" label="Token" value={@config["token"]} />
        <.input_group
          name="encoding_aes_key"
          label="EncodingAESKey"
          value={@config["encoding_aes_key"]}
          type="password"
        />
      </div>

      <h3 class="text-lg font-semibold text-slate-200 pt-4">Sender (API)</h3>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <.input_group name="corp_id" label="Corp ID" value={@config["corp_id"]} />
        <.input_group
          name="corp_secret"
          label="Secret"
          value={@config["corp_secret"]}
          type="password"
        />
        <.input_group name="agent_id" label="Agent ID" value={@config["agent_id"]} type="number" />
        <.input_group
          name="api_base_url"
          label="API Base URL (Optional)"
          value={@config["api_base_url"]}
          placeholder="https://qyapi.weixin.qq.com"
        />
      </div>

      <.save_button />
    </form>
    """
  end

  def telegram_form(assigns) do
    assigns =
      assigns
      |> assign_form_config("telegram")
      |> assign_new(:target, fn -> nil end)

    ~H"""
    <form phx-submit="save" phx-target={@target} class="space-y-6">
      <input type="hidden" name="adapter" value="telegram" />

      <.toggle_enabled enabled={@enabled} label="Enable Telegram Bot" />

      <div class="grid grid-cols-1 gap-4">
        <.input_group name="bot_token" label="Bot Token" value={@config["bot_token"]} type="password" />
      </div>

      <.save_button />
    </form>
    """
  end

  def discord_form(assigns) do
    assigns =
      assigns
      |> assign_form_config("discord")
      |> assign_new(:target, fn -> nil end)

    ~H"""
    <form phx-submit="save" phx-target={@target} class="space-y-6">
      <input type="hidden" name="adapter" value="discord" />

      <.toggle_enabled enabled={@enabled} label="Enable Discord Bot" />

      <h3 class="text-lg font-semibold text-slate-200 pt-2">Bot Settings</h3>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <.input_group name="bot_token" label="Bot Token" value={@config["bot_token"]} type="password" />
        <.input_group name="client_id" label="Application ID" value={@config["client_id"]} />
      </div>

      <h3 class="text-lg font-semibold text-slate-200 pt-4">Permissions</h3>
      <div>
        <.input_group
          name="channel_allowlist"
          label="Channel Allowlist (Comma separated IDs)"
          value={@config["channel_allowlist"]}
          placeholder="123456789, 987654321"
        />
        <p class="text-xs text-slate-400 mt-2">
          Leave empty to allow all channels the bot can access.
        </p>
      </div>

      <.save_button />
    </form>
    """
  end

  # --- Components ---

  def toggle_enabled(assigns) do
    ~H"""
    <div class="flex items-center space-x-3 pb-4 mb-6 border-b border-slate-700">
      <input
        type="checkbox"
        name="enabled"
        id={"enabled_#{@label}"}
        checked={@enabled}
        class="rounded border-slate-600 bg-slate-800 text-teal-600 focus:ring-teal-500 focus:ring-offset-slate-900"
      />
      <label for={"enabled_#{@label}"} class="text-base font-semibold text-slate-200">{@label}</label>
    </div>
    """
  end

  def input_group(assigns) do
    assigns = assign_new(assigns, :type, fn -> "text" end)
    assigns = assign_new(assigns, :placeholder, fn -> "" end)
    assigns = assign(assigns, :is_password, assigns[:type] == "password")

    assigns =
      assign(assigns, :input_id, "input_#{assigns[:name]}_#{:erlang.unique_integer([:positive])}")

    ~H"""
    <div>
      <label class="block text-sm font-medium mb-2 text-slate-300">{@label}</label>
      <div class="relative">
        <input
          id={@input_id}
          type={@type}
          name={@name}
          value={@value}
          placeholder={@placeholder}
          class={[
            "w-full rounded-lg border-slate-700 bg-slate-800 text-slate-200 placeholder-slate-500 focus:border-teal-500 focus:ring-teal-500 focus:ring-offset-slate-900 sm:text-sm transition-colors",
            @is_password && "pr-10"
          ]}
        />
        <%= if @is_password do %>
          <button
            type="button"
            onclick={"
              const input = document.getElementById('#{@input_id}');
              const icon = this.querySelector('svg');
              if (input.type === 'password') {
                input.type = 'text';
                icon.innerHTML = '<path stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"M3.98 8.223A10.477 10.477 0 001.934 12C3.226 16.338 7.244 19.5 12 19.5c.993 0 1.953-.138 2.863-.395M6.228 6.228A10.45 10.45 0 0112 4.5c4.756 0 8.773 3.162 10.065 7.498a10.523 10.523 0 01-4.293 5.774M6.228 6.228L3 3m3.228 3.228l3.65 3.65m7.894 7.894L21 21m-3.228-3.228l-3.65-3.65m0 0a3 3 0 10-4.243-4.243m4.242 4.242L9.88 9.88\" />';
              } else {
                input.type = 'password';
                icon.innerHTML = '<path stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"M2.036 12.322a1.012 1.012 0 010-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178z\" /><path stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"M15 12a3 3 0 11-6 0 3 3 0 016 0z\" />';
              }
            "}
            class="absolute inset-y-0 right-0 flex items-center pr-3 text-slate-400 hover:text-slate-200 transition-colors"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
              class="w-5 h-5"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M2.036 12.322a1.012 1.012 0 010-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178z"
              />
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
              />
            </svg>
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  def select_group(assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium mb-2 text-slate-300">{@label}</label>
      <select
        name={@name}
        class="w-full rounded-lg border-slate-700 bg-slate-800 text-slate-200 focus:border-teal-500 focus:ring-teal-500 focus:ring-offset-slate-900 sm:text-sm transition-colors"
      >
        <%= for opt <- @options do %>
          <option value={opt} selected={@value == opt}>{String.capitalize(opt)}</option>
        <% end %>
      </select>
    </div>
    """
  end

  def save_button(assigns) do
    ~H"""
    <div class="pt-6 flex justify-end">
      <button
        type="submit"
        class="px-6 py-2.5 bg-teal-600 text-white rounded-lg hover:bg-teal-500 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-teal-500 focus:ring-offset-slate-900 transition-all shadow-lg shadow-teal-500/20 font-medium"
      >
        Save Configuration
      </button>
    </div>
    """
  end

  defp assign_form_config(assigns, adapter) do
    assign(assigns,
      config: get_config(assigns.configs, adapter),
      enabled: get_enabled(assigns.configs, adapter)
    )
  end

  defp get_config(configs, adapter) do
    case Enum.find(configs, fn c -> c.adapter == adapter end) do
      nil -> %{}
      record -> record.config
    end
  end

  defp get_enabled(configs, adapter) do
    case Enum.find(configs, fn c -> c.adapter == adapter end) do
      nil -> false
      record -> record.enabled
    end
  end

  defp config_params_for_adapter(adapter, params) do
    case adapter do
      "dingtalk" ->
        %{
          "client_id" => params["client_id"],
          "client_secret" => params["client_secret"],
          "enable_ai_card" => Map.has_key?(params, "enable_ai_card"),
          "dm_policy" => params["dm_policy"],
          "group_policy" => params["group_policy"]
        }

      "feishu" ->
        %{
          "app_id" => params["app_id"],
          "app_secret" => params["app_secret"],
          "encrypt_key" => params["encrypt_key"],
          "verification_token" => params["verification_token"],
          "mode" => params["mode"]
        }

      "wecom" ->
        %{
          "token" => params["token"],
          "encoding_aes_key" => params["encoding_aes_key"],
          "corp_id" => params["corp_id"],
          "corp_secret" => params["corp_secret"],
          "agent_id" => params["agent_id"] |> parse_int(),
          "api_base_url" => params["api_base_url"]
        }

      "telegram" ->
        %{
          "bot_token" => params["bot_token"]
        }

      "discord" ->
        %{
          "bot_token" => params["bot_token"],
          "client_id" => params["client_id"],
          "channel_allowlist" => params["channel_allowlist"]
        }

      _ ->
        %{}
    end
  end

  defp parse_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_int(_), do: nil
end
