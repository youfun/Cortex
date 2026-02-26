defmodule CortexWeb.FileBrowserComponent do
  use CortexWeb, :live_component

  alias Cortex.Workspaces

  def mount(socket) do
    {:ok,
     assign(socket,
       current_path: Workspaces.ensure_workspace_root!(),
       items: [],
       selected_path: nil,
       error: nil
     )}
  end

  def update(assigns, socket) do
    # Use initial_path if provided and current_path is not set (first load),
    # or if we want to reset it.
    path =
      assigns[:initial_path] || socket.assigns.current_path || Workspaces.ensure_workspace_root!()

    # Initialize with the path
    socket =
      socket
      |> assign(assigns)
      |> assign(current_path: path)
      |> assign(selected_path: path)
      |> load_items(path)

    {:ok, socket}
  end

  def handle_event("navigate", %{"path" => path}, socket) do
    if File.dir?(path) do
      {:noreply,
       socket
       |> assign(current_path: path, selected_path: path)
       |> load_items(path)}
    else
      {:noreply, put_flash(socket, :error, "Not a directory")}
    end
  end

  def handle_event("go_up", _, socket) do
    parent = Path.dirname(socket.assigns.current_path)

    {:noreply,
     socket
     |> assign(current_path: parent, selected_path: parent)
     |> load_items(parent)}
  end

  def handle_event("select_item", %{"path" => path}, socket) do
    # When clicking an item, if it's a directory, we select it visually.
    # Double click could enter it? For now single click selects.
    {:noreply, assign(socket, selected_path: path)}
  end

  def handle_event("confirm_selection", _, socket) do
    path = socket.assigns.selected_path || socket.assigns.current_path
    # Send context selection event (distinguish between file and folder)
    send(self(), {:context_selected, path})
    {:noreply, socket}
  end

  def handle_event("open_in_editor", %{"path" => path}, socket) do
    # Send message to parent LiveView to open file in editor
    send(self(), {:open_file_in_editor, path})
    {:noreply, socket}
  end

  defp load_items(socket, path) do
    case File.ls(path) do
      {:ok, files} ->
        items =
          files
          |> Enum.map(fn name ->
            full_path = Path.join(path, name)
            is_dir = File.dir?(full_path)
            %{name: name, path: full_path, is_dir: is_dir}
          end)
          # Folders first, then files, sorted by name
          |> Enum.sort_by(fn item -> {not item.is_dir, item.name} end)

        assign(socket, items: items, error: nil)

      {:error, reason} ->
        assign(socket, items: [], error: "Error accessing path: #{inspect(reason)}")
    end
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-[500px]">
      <!-- Breadcrumbs / Current Path -->
      <div class="flex items-center space-x-2 mb-3 p-2 bg-slate-950 rounded border border-slate-700">
        <button
          phx-click="go_up"
          phx-target={@myself}
          class="p-1.5 hover:bg-slate-800 rounded text-slate-400 hover:text-white transition-colors"
          title="Go Up"
        >
          <.icon name="hero-arrow-up" class="w-4 h-4" />
        </button>
        <div class="flex-1 text-xs font-mono text-slate-300 truncate px-2" title={@current_path}>
          {@current_path}
        </div>
      </div>
      
    <!-- File List -->
      <div class="flex-1 overflow-y-auto border border-slate-700 rounded-xl bg-slate-950/50 p-2 space-y-1 custom-scrollbar">
        <%= if @error do %>
          <div class="flex flex-col items-center justify-center h-full text-red-400 space-y-2">
            <.icon name="hero-exclamation-triangle" class="w-8 h-8 opacity-50" />
            <span class="text-sm">{@error}</span>
          </div>
        <% else %>
          <%= if Enum.empty?(@items) do %>
            <div class="flex flex-col items-center justify-center h-full text-slate-500 space-y-2">
              <.icon name="hero-folder-open" class="w-8 h-8 opacity-20" />
              <span class="text-xs">Empty folder</span>
            </div>
          <% else %>
            <%= for item <- @items do %>
              <div class="flex items-center space-x-1 group">
                <%!-- Navigation Button (only for folders) --%>
                <%= if item.is_dir do %>
                  <button
                    phx-click="navigate"
                    phx-value-path={item.path}
                    phx-target={@myself}
                    class="p-2 text-slate-500 hover:text-teal-400 hover:bg-slate-800 rounded transition-colors"
                    title="Enter folder"
                  >
                    <.icon name="hero-arrow-right-circle" class="w-4 h-4" />
                  </button>
                <% else %>
                  <button
                    phx-click="open_in_editor"
                    phx-value-path={item.path}
                    phx-target={@myself}
                    class="p-2 text-slate-500 hover:text-teal-400 hover:bg-slate-800 rounded transition-colors"
                    title="Open in editor"
                  >
                    <.icon name="hero-pencil-square" class="w-4 h-4" />
                  </button>
                <% end %>

                <%!-- Selection Button --%>
                <button
                  phx-click="select_item"
                  phx-value-path={item.path}
                  phx-target={@myself}
                  class={[
                    "flex-1 flex items-center space-x-3 px-3 py-2 rounded-lg text-sm transition-all text-left",
                    @selected_path == item.path &&
                      "bg-teal-600 text-white shadow-lg shadow-teal-500/20",
                    @selected_path != item.path &&
                      "text-slate-300 hover:bg-slate-800 hover:text-white"
                  ]}
                >
                  <%= if item.is_dir do %>
                    <.icon
                      name="hero-folder"
                      class={
                        Enum.join(
                          [
                            "w-5 h-5 flex-shrink-0",
                            if(@selected_path == item.path, do: "text-white", else: ""),
                            if(@selected_path != item.path,
                              do: "text-teal-400 group-hover:text-teal-300",
                              else: ""
                            )
                          ],
                          " "
                        )
                      }
                    />
                  <% else %>
                    <.icon
                      name="hero-document"
                      class={
                        Enum.join(
                          [
                            "w-5 h-5 flex-shrink-0",
                            if(@selected_path == item.path, do: "text-white", else: ""),
                            if(@selected_path != item.path,
                              do: "text-slate-400 group-hover:text-slate-300",
                              else: ""
                            )
                          ],
                          " "
                        )
                      }
                    />
                  <% end %>
                  <span class="truncate font-medium">{item.name}</span>
                </button>
              </div>
            <% end %>
          <% end %>
        <% end %>
      </div>
      
    <!-- Footer / Actions -->
      <div class="mt-4 pt-4 border-t border-slate-700/50 flex justify-between items-center">
        <div class="text-xs text-slate-500 truncate max-w-[50%]">
          <%= if @selected_path do %>
            Selected: <span class="text-teal-300">#{Path.basename(@selected_path)}</span>
          <% else %>
            No selection
          <% end %>
        </div>

        <div class="flex space-x-3">
          <button
            type="button"
            phx-click="close_add_folder_modal"
            class="px-4 py-2 border border-slate-600 hover:bg-slate-700 text-slate-300 text-sm font-bold rounded-xl transition-colors"
          >
            Cancel
          </button>
          <button
            type="button"
            phx-click="confirm_selection"
            phx-target={@myself}
            class="px-5 py-2 bg-teal-600 hover:bg-teal-500 text-white text-sm font-bold rounded-xl transition-all shadow-lg shadow-teal-500/20 flex items-center space-x-2"
          >
            <.icon name="hero-check" class="w-4 h-4" />
            <span>Confirm Selection</span>
          </button>
        </div>
      </div>
    </div>
    """
  end
end
