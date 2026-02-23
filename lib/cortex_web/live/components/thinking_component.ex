defmodule CortexWeb.Components.ThinkingComponent do
  @moduledoc """
  思考组件：显示 Agent 的思考过程。
  """

  use Phoenix.LiveComponent

  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full bg-slate-900 rounded-lg overflow-hidden border border-slate-800">
      <div class="flex items-center justify-between px-4 py-2 bg-slate-800/50 border-b border-slate-700/50">
        <div class="flex items-center space-x-2">
          <div class="animate-pulse w-2 h-2 rounded-full bg-teal-400"></div>
          <span class="text-xs font-semibold text-teal-300 uppercase tracking-wider">
            Agent Thinking
          </span>
        </div>
      </div>
      <div class="flex-1 p-4 overflow-auto text-slate-300 italic font-serif text-sm leading-relaxed">
        <%= if @thinking_text && @thinking_text != "" do %>
          <div class="whitespace-pre-wrap">
            {@thinking_text}
          </div>
        <% else %>
          <div class="flex items-center justify-center h-full text-slate-500 not-italic font-sans">
            <span class="animate-pulse">Waiting for thoughts...</span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def mount(socket) do
    {:ok, assign(socket, thinking_text: "")}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end
end
