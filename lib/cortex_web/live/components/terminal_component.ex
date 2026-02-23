defmodule CortexWeb.Components.TerminalComponent do
  @moduledoc """
  终端组件：订阅 shell.output 信号并渲染输出。
  """

  use Phoenix.LiveComponent

  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full bg-slate-900 rounded-lg overflow-hidden border border-slate-800">
      <div class="flex items-center justify-between px-4 py-2 bg-slate-800 border-b border-slate-700">
        <div class="flex items-center space-x-2">
          <div class="w-3 h-3 rounded-full bg-red-500"></div>
          <div class="w-3 h-3 rounded-full bg-yellow-500"></div>
          <div class="w-3 h-3 rounded-full bg-green-500"></div>
          <span class="ml-2 text-xs font-mono text-slate-400">Terminal</span>
        </div>
      </div>
      <div
        id="terminal-output"
        class="flex-1 font-mono text-sm text-green-400 p-4 overflow-auto"
        phx-hook="Terminal"
        phx-update="stream"
      >
        <div :for={{dom_id, line} <- @streams.output_lines} id={dom_id} class="whitespace-pre-wrap">
          {line.content}
        </div>
      </div>
    </div>
    """
  end

  def mount(socket) do
    {:ok, stream(socket, :output_lines, [])}
  end

  def update(%{shell_chunk: chunk}, socket) do
    line = %{id: System.unique_integer([:positive]), content: chunk}
    {:ok, stream_insert(socket, :output_lines, line)}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end
end
