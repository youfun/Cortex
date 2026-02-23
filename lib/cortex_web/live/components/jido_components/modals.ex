defmodule CortexWeb.JidoComponents.Modals do
  @moduledoc """
  Modal components for the Cortex UI.
  """
  use CortexWeb, :html
  alias CortexWeb.FileBrowserComponent

  @doc """
  Add Folder Modal component.
  """
  def add_folder_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm">
      <div class="bg-slate-800 border border-slate-700 rounded-2xl shadow-2xl max-w-2xl w-full mx-4 overflow-hidden">
        <!-- Header -->
        <div class="bg-gradient-to-r from-slate-700/40 to-teal-900/20 px-6 py-4 border-b border-slate-700">
          <div class="flex items-center justify-between">
            <div class="flex items-center space-x-3">
              <div class="p-2 bg-teal-500/20 rounded-lg">
                <.icon name="hero-folder-plus" class="w-6 h-6 text-teal-400" />
              </div>
              <div>
                <h3 class="text-lg font-bold text-white">Add Path</h3>
                <p class="text-sm text-slate-400">Select directory or file to authorize Agent access</p>
              </div>
            </div>
            <button
              phx-click="close_add_folder_modal"
              class="p-1.5 hover:bg-slate-700 rounded-lg transition-colors"
            >
              <.icon name="hero-x-mark" class="w-5 h-5 text-slate-400" />
            </button>
          </div>
        </div>
        
    <!-- Body -->
        <div class="px-6 py-4">
          <.live_component
            module={FileBrowserComponent}
            id="file-browser"
            initial_path={@folder_path}
          />
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Archived Conversations Modal component.
  """
  def archived_conversations_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm">
      <div class="bg-slate-800 border border-slate-700 rounded-2xl shadow-2xl max-w-2xl w-full mx-4 overflow-hidden flex flex-col max-h-[80vh]">
        <!-- Header -->
        <div class="bg-gradient-to-r from-slate-700/50 to-slate-600/50 px-6 py-4 border-b border-slate-700">
          <div class="flex items-center justify-between">
            <div class="flex items-center space-x-3">
              <div class="p-2 bg-slate-600/30 rounded-lg">
                <.icon name="hero-archive-box" class="w-6 h-6 text-slate-400" />
              </div>
              <div>
                <h3 class="text-lg font-bold text-white">Archived Conversations</h3>
                <p class="text-sm text-slate-400">Manage archived conversation history</p>
              </div>
            </div>
            <button
              phx-click="close_archived_modal"
              class="p-1.5 hover:bg-slate-700 rounded-lg transition-colors"
            >
              <.icon name="hero-x-mark" class="w-5 h-5 text-slate-400" />
            </button>
          </div>
        </div>
        
    <!-- Body -->
        <div class="flex-1 overflow-y-auto px-6 py-4">
          <%= if Enum.empty?(@archived_conversations) do %>
            <div class="text-center py-12">
              <div class="inline-flex p-4 bg-slate-900/50 rounded-full mb-4">
                <.icon name="hero-archive-box" class="w-12 h-12 text-slate-600" />
              </div>
              <h4 class="text-lg font-semibold text-slate-400 mb-2">No Archived Conversations</h4>
              <p class="text-sm text-slate-500">You can archive conversations you no longer use here</p>
            </div>
          <% else %>
            <div class="space-y-2">
              <%= for conv <- @archived_conversations do %>
                <div class="bg-slate-900/50 border border-slate-700 rounded-lg p-4 hover:border-slate-600 transition-colors">
                  <div class="flex items-start justify-between">
                    <div class="flex-1 min-w-0 mr-4">
                      <div class="flex items-center space-x-2 mb-1">
                        <span class="text-sm font-medium text-slate-200 truncate" title={conv.title}>
                          {conv.title}
                        </span>
                      </div>
                      <div class="text-xs text-slate-500">
                        Archived at {format_relative_time(conv.updated_at)}
                      </div>
                    </div>
                    <div class="flex items-center space-x-2 flex-shrink-0">
                      <button
                        phx-click="restore_conversation"
                        phx-value-id={conv.id}
                        class="p-2 hover:bg-green-500/10 text-slate-500 hover:text-green-400 rounded-lg transition-colors"
                        title="Restore conversation"
                      >
                        <.icon name="hero-arrow-uturn-left" class="w-4 h-4" />
                      </button>
                      <button
                        phx-click="delete_archived_conversation"
                        phx-value-id={conv.id}
                        data-confirm="Are you sure you want to permanently delete this conversation? This action cannot be undone."
                        class="p-2 hover:bg-red-500/10 text-slate-500 hover:text-red-400 rounded-lg transition-colors"
                        title="Permanently delete"
                      >
                        <.icon name="hero-trash" class="w-4 h-4" />
                      </button>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
        
    <!-- Footer -->
        <div class="px-6 py-4 bg-slate-900/30 border-t border-slate-700 flex justify-between items-center">
          <div class="text-xs text-slate-500">
            Total {length(@archived_conversations)} archived conversations
          </div>
          <button
            phx-click="close_archived_modal"
            class="px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white text-sm font-medium rounded-lg transition-colors"
          >
            Close
          </button>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Permission Request Modal component.
  """
  def permission_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm">
      <div class="bg-slate-800 border border-slate-700 rounded-2xl shadow-2xl max-w-md w-full mx-4 overflow-hidden">
        <!-- Header -->
        <div class="bg-gradient-to-r from-amber-600/20 to-orange-600/20 px-6 py-4 border-b border-slate-700">
          <div class="flex items-center space-x-3">
            <div class="p-2 bg-amber-500/20 rounded-lg">
              <.icon name="hero-shield-exclamation" class="w-6 h-6 text-amber-400" />
            </div>
            <div>
              <h3 class="text-lg font-bold text-white">安全审批</h3>
              <p class="text-sm text-slate-400">Agent 请求执行敏感操作</p>
            </div>
          </div>
        </div>
        
    <!-- Body -->
        <div class="px-6 py-4">
          <%= if @request do %>
            <div class="bg-slate-900/50 rounded-xl p-4 border border-slate-700 space-y-3">
              <%= if @request[:command] || (@request[:params] && (@request.params[:command] || @request.params["command"])) do %>
                <div>
                  <div class="text-xs text-slate-500 uppercase font-bold tracking-wider mb-1">
                    Requested Command
                  </div>
                  <div class="text-sm font-mono text-teal-300 break-all bg-slate-950/50 p-2 rounded">
                    {(@request.command || @request.params[:command] || @request.params["command"])}
                  </div>
                </div>
                <div>
                  <div class="text-xs text-slate-500 uppercase font-bold tracking-wider mb-1">
                    Approval Reason
                  </div>
                  <div class="text-sm text-amber-200">
                    {(@request.reason || @request.params[:reason] || @request.params["reason"] || "No reason provided")}
                  </div>
                </div>
              <% else %>
                <div>
                  <div class="text-xs text-slate-500 uppercase font-bold tracking-wider mb-1">
                    Requested Operation
                  </div>
                  <div class="flex items-center space-x-2">
                    <.icon name={action_icon(@request.action)} class="w-4 h-4 text-teal-400" />
                    <span class="text-sm font-medium text-slate-200">
                      {format_action_name(@request.action)}
                    </span>
                  </div>
                </div>

                <div>
                  <div class="text-xs text-slate-500 uppercase font-bold tracking-wider mb-1">
                    Requested Path
                  </div>
                  <div class="text-sm font-mono text-teal-300 break-all bg-slate-950/50 p-2 rounded">
                    {@request.path}
                  </div>
                </div>
              <% end %>

              <%= if @request.action == :write or @request[:tool] == "shell" or (@request[:params] && (@request.params[:tool] || @request.params["tool"]) == "shell") do %>
                <div class="flex items-start space-x-2 text-amber-400/80 text-xs">
                  <.icon name="hero-exclamation-triangle" class="w-4 h-4 flex-shrink-0 mt-0.5" />
                  <span>Sensitive operation may modify system state or file content, please confirm.</span>
                </div>
              <% end %>
            </div>

            <p class="mt-4 text-sm text-slate-400">
              In zero-trust mode, Agent requires your explicit authorization to execute this operation.
            </p>
          <% else %>
            <div class="text-center text-slate-500 py-4">
              No pending approval requests
            </div>
          <% end %>
        </div>
        
    <!-- Footer -->
        <div class="px-6 py-4 bg-slate-900/30 border-t border-slate-700 space-y-3">
          <div class="flex space-x-3">
            <button
              phx-click="approve_permission"
              class="flex-1 py-2.5 bg-teal-600 hover:bg-teal-500 text-white text-sm font-bold rounded-xl transition-colors flex items-center justify-center space-x-2"
            >
              <.icon name="hero-check" class="w-4 h-4" />
              <span>Allow Once</span>
            </button>
            <button
              phx-click="reject_permission"
              class="flex-1 py-2.5 bg-slate-700 hover:bg-slate-600 text-white text-sm font-bold rounded-xl transition-colors flex items-center justify-center space-x-2"
            >
              <.icon name="hero-x-mark" class="w-4 h-4" />
              <span>Reject</span>
            </button>
          </div>
          <button
            phx-click="approve_permission_always"
            class="w-full py-2 bg-slate-800 hover:bg-slate-700 text-slate-300 text-xs font-medium rounded-lg transition-colors border border-slate-700"
          >
            Allow this path for current session
          </button>
          <button
            phx-click="close_permission_modal"
            class="w-full py-1.5 text-slate-500 hover:text-slate-400 text-xs transition-colors"
          >
            Decide Later
          </button>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions for permission modal
  defp format_relative_time(nil), do: ""

  defp format_relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86_400)}d ago"
      true -> Calendar.strftime(datetime, "%m/%d")
    end
  end

  defp format_action_name(:read), do: "Read"
  defp format_action_name(:write), do: "Write"
  defp format_action_name(:delete), do: "Delete"
  defp format_action_name(action) when is_atom(action), do: to_string(action)
  defp format_action_name(action) when is_binary(action), do: action
  defp format_action_name(_), do: "Unknown Operation"

  defp action_icon(:read), do: "hero-document-text"
  defp action_icon(:write), do: "hero-pencil-square"
  defp action_icon(:delete), do: "hero-trash"
  defp action_icon(_), do: "hero-question-mark-circle"
end
