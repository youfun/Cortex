defmodule CortexWeb.JidoComponents.ChatPanel do
  @moduledoc """
  Chat panel component with message display components.
  """
  use CortexWeb, :html

  @doc """
  Main Chat Panel component.
  """
  def chat_panel(assigns) do
    assigns =
      assign(
        assigns,
        :selected_model,
        Enum.find(assigns.models, &(&1.id == assigns.selected_model_id))
      )

    assigns =
      assign(
        assigns,
        :all_agents,
        [
          %{
            id: nil,
            name: gettext("Native (Jido)"),
            description: gettext("Use Jido local agent"),
            status: "online",
            sessions_count: 0
          }
          | assigns.agents || []
        ]
      )

    assigns =
      assign(
        assigns,
        :selected_agent,
        Enum.find(assigns.all_agents, &(&1.id == assigns.selected_agent_id))
      )

    ~H"""
    <div class="flex-1 flex flex-col h-full relative">
      <!-- Selectors Area -->
      <div class="absolute top-4 right-4 z-20 flex items-start space-x-2">
          <!-- Add Folder Button -->
          <button
            phx-click="open_add_folder_modal"
            class="flex items-center space-x-2 px-3 py-1.5 bg-slate-800 border border-slate-700 rounded-lg text-xs hover:bg-slate-700 transition-colors"
            title="Add directory or file to authorize Agent access"
          >
            <.icon name="hero-folder-plus" class="w-4 h-4" />
            <span>Add Path</span>
          </button>

    <!-- Agent Selector -->
          <div class="relative">
            <button
              phx-click="toggle_agent_selector"
              class="flex items-center space-x-2 px-3 py-1.5 bg-slate-800 border border-slate-700 rounded-lg text-xs hover:bg-slate-700 transition-colors"
            >
              <span>{@selected_agent[:name] || "Select Agent"}</span>
              <.icon name="hero-chevron-down" class="w-3 h-3" />
            </button>

            <div
              :if={@show_agent_selector}
              class="absolute right-0 mt-2 w-56 bg-slate-800 border border-slate-700 rounded-xl shadow-2xl py-2 z-30"
            >
              <div class="px-3 py-2 text-[10px] font-bold text-slate-500 uppercase tracking-widest">
                Agents
              </div>
              <%= for agent <- @all_agents do %>
                <button
                  phx-click="select_agent"
                  phx-value-id={agent.id}
                  class={[
                    "w-full text-left px-4 py-2 text-sm flex items-center justify-between hover:bg-slate-700 transition-colors",
                    agent.id == @selected_agent_id && "text-teal-400 bg-teal-500/5",
                    agent.id != @selected_agent_id && "text-slate-300"
                  ]}
                >
                  <div class="flex flex-col">
                    <span>{agent.name}</span>
                    <span class="text-[10px] opacity-50">{agent.status}</span>
                  </div>
                  <.icon :if={agent.id == @selected_agent_id} name="hero-check" class="w-4 h-4" />
                </button>
              <% end %>
              <div :if={Enum.empty?(@all_agents)} class="px-4 py-2 text-xs text-slate-500">
                No agents available
              </div>
            </div>
          </div>

    <!-- Model Selector -->
          <div class="relative">
            <button
              phx-click="toggle_model_selector"
              class="flex items-center space-x-2 px-3 py-1.5 bg-slate-800 border border-slate-700 rounded-lg text-xs hover:bg-slate-700 transition-colors"
            >
              <.icon name="hero-cpu-chip" class="w-4 h-4" />
              <span>{@selected_model[:name] || "Select Model"}</span>
              <.icon name="hero-chevron-down" class="w-3 h-3" />
            </button>

            <div
              :if={@show_model_selector}
              class="absolute right-0 mt-2 w-56 bg-slate-800 border border-slate-700 rounded-xl shadow-2xl py-2 z-30"
            >
              <div class="px-3 py-2 text-[10px] font-bold text-slate-500 uppercase tracking-widest">
                Available Models
              </div>
              <%= for model <- @models do %>
                <button
                  phx-click="select_model"
                  phx-value-id={model.id}
                  class={[
                    "w-full text-left px-4 py-2 text-sm flex items-center justify-between hover:bg-slate-700 transition-colors",
                    model.id == @selected_model_id && "text-teal-400 bg-teal-500/5",
                    model.id != @selected_model_id && "text-slate-300"
                  ]}
                >
                  <div class="flex flex-col">
                    <span>{model.name}</span>
                    <span class="text-[10px] opacity-50">{model.provider}</span>
                  </div>
                  <.icon :if={model.id == @selected_model_id} name="hero-check" class="w-4 h-4" />
                </button>
              <% end %>
            </div>
          </div>
        </div>

    <!-- Messages Area -->
        <div
          id="messages-container"
          phx-hook="ScrollToBottom"
          class="flex-1 overflow-y-auto p-6 space-y-6"
        >
          <div
            id="messages"
            phx-update="stream"
            class="space-y-6"
          >
            <div
              id="messages-empty-placeholder"
              class="hidden only:block text-center text-slate-500 py-12"
            >
              Start a new conversation...
            </div>
            <div
              :for={{dom_id, msg} <- @streams.messages}
              id={dom_id}
              class={[
                "flex",
                message_alignment(msg.message_type)
              ]}
            >
              <.display_message message={msg} />
            </div>
          </div>

    <!-- Streaming Area -->
          <div id="streaming-area" class="space-y-6">
            <div
              :for={{_id, msg} <- @streaming_messages}
              class={[
                "flex",
                message_alignment(msg.message_type)
              ]}
            >
              <.display_message message={msg} />
            </div>

            <div :if={@is_thinking} class="flex justify-start">
              <div class="bg-slate-800 border border-slate-700 rounded-2xl rounded-tl-none px-4 py-3 flex space-x-1">
                <div
                  class="w-1.5 h-1.5 bg-slate-500 rounded-full animate-bounce"
                  style="animation-delay: 0s"
                >
                </div>
                <div
                  class="w-1.5 h-1.5 bg-slate-500 rounded-full animate-bounce"
                  style="animation-delay: 0.1s"
                >
                </div>
                <div
                  class="w-1.5 h-1.5 bg-slate-500 rounded-full animate-bounce"
                  style="animation-delay: 0.2s"
                >
                </div>
              </div>
            </div>

            <div :if={@pending_tool_calls_count > 0} class="flex justify-start">
              <div class="bg-slate-900/70 border border-slate-700 rounded-2xl rounded-tl-none px-3 py-2 flex items-center gap-2 text-xs text-slate-300">
                <div class="w-2 h-2 rounded-full bg-blue-400/70 animate-pulse"></div>
                <span>Tools running...</span>
                <span class="text-[10px] opacity-60">({@pending_tool_calls_count})</span>
              </div>
            </div>
          </div>
        </div>

    <!-- Authorized Folders Bar -->
        <div :if={length(@authorized_paths) > 0} class="px-6 py-2 bg-slate-900/60 border-t border-slate-800/50">
          <div class="flex items-center gap-2 flex-wrap">
            <span class="text-[10px] font-bold text-slate-500 uppercase tracking-wider">Authorized:</span>
            <div :for={path <- @authorized_paths} class="flex items-center gap-1 px-2 py-0.5 bg-teal-500/10 border border-teal-500/20 rounded-md text-xs text-teal-300">
              <.icon name="hero-folder" class="w-3 h-3" />
              <span class="truncate max-w-[200px]">{path}</span>
              <button
                phx-click="remove_authorized_folder"
                phx-value-path={path}
                class="ml-1 p-0.5 hover:bg-red-500/20 rounded text-slate-500 hover:text-red-400 transition-colors"
                title="Remove authorization"
              >
                <.icon name="hero-x-mark" class="w-3 h-3" />
              </button>
            </div>
          </div>
        </div>

    <!-- Input Area -->
        <div class="p-6 bg-slate-900 border-t border-slate-800/50">
          <form phx-submit="send_message" class="relative">
            <textarea
              id="message-input"
              name="message"
              phx-hook="MessageInput"
              rows="1"
              placeholder="Ask anything..."
              class="w-full bg-slate-800 border border-slate-700 rounded-2xl py-4 pl-6 pr-24 text-slate-200 placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-teal-500/50 focus:border-teal-500 transition-all resize-none"
            ></textarea>
            <div class="absolute right-3 bottom-3 flex space-x-2">
              <button
                type="submit"
                class="p-2 bg-teal-600 text-white rounded-xl hover:bg-teal-500 transition-colors shadow-lg shadow-teal-500/20"
              >
                <.icon name="hero-paper-airplane" class="w-5 h-5" />
              </button>
            </div>
          </form>

        </div>
    </div>
    """
  end

  defp format_message_time(%{inserted_at: %DateTime{} = datetime}) do
    DateTime.to_iso8601(datetime)
  end

  defp format_message_time(%{timestamp: timestamp}) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _} -> DateTime.to_iso8601(dt)
      _ -> timestamp
    end
  end

  defp format_message_time(_), do: ""

  def display_message(assigns) do
    ~H"""
    <div class="py-1">
      <%= case @message.content_type do %>
        <% "text" -> %>
          <.text_message message={@message} />
        <% "thinking" -> %>
          <.thinking_message message={@message} />
        <% "tool_call" -> %>
          <.tool_call_message message={@message} />
        <% "tool_result" -> %>
          <.tool_result_message message={@message} />
        <% "notification" -> %>
          <.notification_message message={@message} />
        <% "error" -> %>
          <.error_message message={@message} />
        <% _ -> %>
          <.text_message message={@message} />
      <% end %>
    </div>
    """
  end

  def text_message(assigns) do
    assigns = assign(assigns, :text, message_text(assigns.message))

    ~H"""
    <%= case @message.message_type do %>
      <% "user" -> %>
        <div class="max-w-[80%] rounded-2xl px-4 py-3 shadow-sm bg-teal-600 text-white rounded-tr-none">
          <div class="text-sm whitespace-pre-wrap">{@text}</div>
          <div class="text-[10px] mt-1 opacity-50 text-right">
            <span phx-hook="LocalTime" data-utc-time={format_message_time(@message)} id={"time-#{@message.id}"}></span>
          </div>
        </div>
      <% "assistant" -> %>
        <div class="max-w-[80%] rounded-2xl px-4 py-3 shadow-sm bg-slate-800 text-slate-200 border border-slate-700 rounded-tl-none">
          <div class="text-sm markdown-content">
            {CortexWeb.Markdown.to_safe_html(@text)}
          </div>
          <div class="text-[10px] mt-1 opacity-50 text-left">
            <span phx-hook="LocalTime" data-utc-time={format_message_time(@message)} id={"time-#{@message.id}"}></span>
          </div>
        </div>
      <% _ -> %>
        <div class="max-w-[90%] rounded-xl px-4 py-2 bg-slate-900/50 border border-slate-800 text-slate-400">
          <div class="flex items-center gap-2 mb-1">
            <.icon name="hero-cog-6-tooth" class="w-3 h-3" />
            <span class="text-[10px] font-bold uppercase tracking-wider">System</span>
          </div>
          <div class="text-xs italic">{@text}</div>
        </div>
    <% end %>
    """
  end

  def thinking_message(assigns) do
    assigns = assign(assigns, :text, message_text(assigns.message))

    ~H"""
    <div class="max-w-[80%] rounded-2xl px-4 py-3 shadow-sm bg-slate-900/70 text-slate-400 border border-slate-800 rounded-tl-none">
      <div class="text-sm italic whitespace-pre-wrap">{@text}</div>
      <div class="text-[10px] mt-1 opacity-50 text-left">
        <span phx-hook="LocalTime" data-utc-time={format_message_time(@message)} id={"time-#{@message.id}"}></span>
      </div>
    </div>
    """
  end

  def tool_call_message(assigns) do
    ~H"""
    <div class={[
      "flex items-center gap-2 px-3 py-2 rounded-lg text-sm",
      @message.status == "pending" && "bg-yellow-900/30 text-yellow-300",
      @message.status == "executing" && "bg-blue-900/30 text-blue-300 animate-pulse",
      @message.status == "completed" && "bg-green-900/30 text-green-300",
      @message.status == "failed" && "bg-red-900/30 text-red-300"
    ]}>
      <.icon name="hero-wrench-screwdriver" class="w-4 h-4 flex-shrink-0" />
      <span class="font-mono">{(@message.content || %{})["name"]}</span>
      <span class="text-xs opacity-60">{status_label(@message.status)}</span>
    </div>
    """
  end

  def tool_result_message(assigns) do
    ~H"""
    <div class="max-w-[90%] rounded-xl px-4 py-2 bg-slate-900/50 border border-slate-700/30 text-teal-300">
      <div class="flex items-center gap-2 mb-1 whitespace-nowrap">
        <.icon name="hero-wrench-screwdriver" class="w-3 h-3" />
        <span class="text-[10px] font-bold uppercase tracking-wider">Tool Result</span>
        <span class="text-[10px] opacity-60">{(@message.content || %{})["name"]}</span>
      </div>
      <div class="text-xs font-mono whitespace-pre-wrap overflow-x-auto max-h-48">
        {(@message.content || %{})["content"]}
      </div>
    </div>
    """
  end

  def notification_message(assigns) do
    assigns = assign(assigns, :text, message_text(assigns.message))

    ~H"""
    <div class="max-w-[90%] rounded-xl px-4 py-2 bg-slate-900/50 border border-slate-800 text-slate-400">
      <div class="flex items-center gap-2 mb-1">
        <.icon name="hero-cog-6-tooth" class="w-3 h-3" />
        <span class="text-[10px] font-bold uppercase tracking-wider">System</span>
      </div>
      <div class="text-xs italic">{@text}</div>
    </div>
    """
  end

  def error_message(assigns) do
    assigns = assign(assigns, :text, message_text(assigns.message))

    ~H"""
    <div class="max-w-[90%] rounded-xl px-4 py-2 bg-red-900/20 border border-red-900/40 text-red-300">
      <div class="flex items-center gap-2 mb-1">
        <.icon name="hero-exclamation-triangle" class="w-3 h-3" />
        <span class="text-[10px] font-bold uppercase tracking-wider">Error</span>
      </div>
      <div class="text-xs italic">{@text}</div>
    </div>
    """
  end

  defp message_alignment("user"), do: "justify-end"
  defp message_alignment(_), do: "justify-start"

  defp message_text(message) do
    content = message.content || %{}
    Map.get(content, "text", "")
  end

  defp status_label("pending"), do: "Pending..."
  defp status_label("executing"), do: "Executing..."
  defp status_label("completed"), do: "✓ Completed"
  defp status_label("failed"), do: "✗ Failed"
  defp status_label(_), do: ""
end
