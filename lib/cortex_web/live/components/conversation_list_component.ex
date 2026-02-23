defmodule CortexWeb.ConversationListComponent do
  @moduledoc """
  Conversation list component for the sidebar.
  Displays all conversations with actions (switch, archive, delete).
  """
  use CortexWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <%!-- New Conversation Button --%>
      <div class="p-4">
        <button
          phx-click="new_conversation"
          id="btn-new-conversation"
          class="w-full flex items-center justify-center gap-2 bg-teal-600 text-white px-4 py-2 rounded-lg hover:bg-teal-500 transition-colors"
        >
          <.icon name="hero-plus" class="w-5 h-5" />
          <span class="text-sm font-medium">{gettext("New Chat")}</span>
        </button>
      </div>

      <%!-- Conversation List --%>
      <div id="conversations" phx-update="stream" class="flex-1 overflow-y-auto">
        <div :for={{dom_id, conv} <- @streams.conversations} id={dom_id} class="group">
          <div
            phx-click="switch_conversation"
            phx-value-id={conv.id}
            class={[
              "px-4 py-3 cursor-pointer border-l-2 transition-colors",
              conv.id == @current_conversation_id && "bg-slate-800 border-teal-500",
              conv.id != @current_conversation_id && "border-transparent hover:bg-slate-800"
            ]}
          >
            <div class="flex items-start justify-between gap-2">
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-1">
                  <.icon
                    :if={conv.is_pinned}
                    name="hero-bookmark-solid"
                    class="w-3 h-3 text-amber-400"
                  />
                  <span class={[
                    "text-sm font-medium truncate",
                    conv.id == @current_conversation_id && "text-white",
                    conv.id != @current_conversation_id && "text-slate-300"
                  ]}>
                    {conv.title}
                  </span>
                </div>
                <div class="text-xs text-slate-500 mt-1">
                  {format_relative_time(conv.last_used_at || conv.updated_at)}
                </div>
              </div>
              <div class="flex items-center space-x-1">
                <button
                  phx-click="archive_conversation"
                  phx-value-id={conv.id}
                  class="opacity-0 group-hover:opacity-100 p-1 text-slate-500 hover:text-amber-400 transition-opacity"
                  title={gettext("Archive Conversation")}
                >
                  <.icon name="hero-archive-box" class="w-4 h-4" />
                </button>
                <button
                  phx-click="delete_conversation"
                  phx-value-id={conv.id}
                  class="opacity-0 group-hover:opacity-100 p-1 text-slate-500 hover:text-red-400 transition-opacity"
                  data-confirm={gettext("Are you sure you want to delete this conversation?")}
                  title={gettext("Delete Conversation")}
                >
                  <.icon name="hero-trash" class="w-4 h-4" />
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Archived Link --%>
      <div class="p-4 border-t border-slate-800">
        <button
          phx-click="show_archived"
          class="w-full text-sm text-slate-400 hover:text-white transition-colors text-left"
        >
          <.icon name="hero-archive-box" class="w-4 h-4 inline mr-2" />
          Archived ({@archived_count})
        </button>
      </div>
    </div>
    """
  end

  defp format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "Just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end
end
