defmodule CortexWeb.EditorComponent do
  use CortexWeb, :live_component

  alias Cortex.Security
  alias Cortex.Workspaces

  @max_file_size 1_048_576  # 1MB

  def mount(socket) do
    {:ok,
     assign(socket,
       open_tabs: [],
       active_tab: nil,
       selected_text: nil,
       cursor: %{line: 1, column: 1},
       save_status: :saved
     )}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)
    
    socket = cond do
      Map.has_key?(assigns, :action) && assigns.action == :open_file ->
        handle_open_file(socket, assigns.path)
      
      Map.has_key?(assigns, :action) && assigns.action == :refresh_file ->
        handle_refresh_file(socket, assigns.path)
      
      true ->
        socket
    end
    
    {:ok, socket}
  end

  defp handle_refresh_file(socket, path) do
    # Check if file is currently open
    tab = Enum.find(socket.assigns.open_tabs, fn t -> t.path == path end)
    
    if tab do
      case validate_and_read_file(path) do
        {:ok, content, _language} ->
          # Update tab content
          tabs = Enum.map(socket.assigns.open_tabs, fn t ->
            if t.path == path do
              %{t | content: content, original_content: content, dirty: false}
            else
              t
            end
          end)
          
          # Push update to CodeMirror editor via hook
          socket
          |> assign(open_tabs: tabs, save_status: :saved)
          |> push_event("cm:set_value", %{value: content, path: path})

        {:error, _reason} ->
          socket
      end
    else
      socket
    end
  end

  defp handle_open_file(socket, path) do
    case validate_and_read_file(path) do
      {:ok, content, language} ->
        tabs = socket.assigns.open_tabs
        
        # Check if file is already open
        existing_tab = Enum.find(tabs, fn tab -> tab.path == path end)
        
        if existing_tab do
          assign(socket, active_tab: path)
        else
          new_tab = %{
            path: path,
            content: content,
            dirty: false,
            language: language,
            original_content: content
          }
          assign(socket, 
            open_tabs: tabs ++ [new_tab],
            active_tab: path,
            save_status: :saved
          )
        end

      {:error, _reason} ->
        socket
    end
  end

  # Open file in editor
  def handle_event("open_file", %{"path" => path}, socket) do
    case validate_and_read_file(path) do
      {:ok, content, language} ->
        tabs = socket.assigns.open_tabs
        
        # Check if file is already open
        existing_tab = Enum.find(tabs, fn tab -> tab.path == path end)
        
        socket = if existing_tab do
          assign(socket, active_tab: path)
        else
          new_tab = %{
            path: path,
            content: content,
            dirty: false,
            language: language,
            original_content: content
          }
          assign(socket, 
            open_tabs: tabs ++ [new_tab],
            active_tab: path,
            save_status: :saved
          )
        end
        
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to open file: #{reason}")}
    end
  end

  # Content changed from CodeMirror editor
  def handle_event("content_changed", %{"content" => content}, socket) do
    active_path = socket.assigns.active_tab
    
    socket = if active_path do
      tabs = update_tab_content(socket.assigns.open_tabs, active_path, content)
      active_tab = Enum.find(tabs, fn tab -> tab.path == active_path end)
      
      dirty = active_tab && active_tab.original_content != content
      
      assign(socket, 
        open_tabs: tabs,
        save_status: if(dirty, do: :unsaved, else: :saved)
      )
    else
      socket
    end
    
    {:noreply, socket}
  end

  # Text selected in CodeMirror editor
  def handle_event("text_selected", params, socket) do
    %{
      "text" => text,
      "start_line" => start_line,
      "end_line" => end_line
    } = params
    
    socket = assign(socket, 
      selected_text: %{
        text: text,
        line_range: %{start: start_line, end: end_line}
      }
    )
    
    {:noreply, socket}
  end

  # Cursor position changed
  def handle_event("cursor_position_changed", %{"line" => line, "column" => column}, socket) do
    {:noreply, assign(socket, cursor: %{line: line, column: column})}
  end

  # Switch active tab
  def handle_event("switch_tab", %{"path" => path}, socket) do
    {:noreply, assign(socket, active_tab: path)}
  end

  # Close tab
  def handle_event("close_tab", %{"path" => path}, socket) do
    tabs = socket.assigns.open_tabs
    tab = Enum.find(tabs, fn t -> t.path == path end)
    
    socket = if tab && tab.dirty do
      # TODO: Show confirmation dialog
      socket
    else
      new_tabs = Enum.reject(tabs, fn t -> t.path == path end)
      new_active = if socket.assigns.active_tab == path do
        case new_tabs do
          [first | _] -> first.path
          [] -> nil
        end
      else
        socket.assigns.active_tab
      end
      
      assign(socket, open_tabs: new_tabs, active_tab: new_active)
    end
    
    {:noreply, socket}
  end

  # Save file (Ctrl+S)
  def handle_event("save_file", _, socket) do
    active_path = socket.assigns.active_tab
    
    socket = if active_path do
      active_tab = Enum.find(socket.assigns.open_tabs, fn tab -> tab.path == active_path end)
      
      if active_tab && active_tab.dirty do
        case write_file_safely(active_path, active_tab.content) do
          :ok ->
            tabs = update_tab_saved(socket.assigns.open_tabs, active_path, active_tab.content)
            
            # Emit signal for file change
            send(self(), {:file_saved_from_editor, active_path, active_tab.content})
            
            socket
            |> assign(open_tabs: tabs, save_status: :saved)
            |> put_flash(:info, "File saved")

          {:error, reason} ->
            put_flash(socket, :error, "Failed to save: #{reason}")
        end
      else
        socket
      end
    else
      socket
    end
    
    {:noreply, socket}
  end

  # Inject context (selected text or full file)
  def handle_event("inject_context", _, socket) do
    active_path = socket.assigns.active_tab
    
    if active_path do
      active_tab = Enum.find(socket.assigns.open_tabs, fn tab -> tab.path == active_path end)
      
      context_data = if socket.assigns.selected_text do
        %{
          type: :snippet,
          path: active_path,
          content: socket.assigns.selected_text.text,
          line_range: socket.assigns.selected_text.line_range
        }
      else
        %{
          type: :full_file,
          path: active_path,
          content: active_tab.content
        }
      end
      
      send(self(), {:inject_context, context_data})
      
      {:noreply, put_flash(socket, :info, "Context injected")}
    else
      {:noreply, socket}
    end
  end

  # Private helpers

  defp validate_and_read_file(path) do
    workspace_root = Workspaces.ensure_workspace_root!()
    
    with {:ok, validated_path} <- Cortex.Core.Security.validate_path_with_folders(path, workspace_root, []),
         true <- File.exists?(validated_path),
         false <- File.dir?(validated_path),
         {:ok, stat} <- File.stat(validated_path),
         true <- stat.size <= @max_file_size do
      
      case File.read(validated_path) do
        {:ok, content} ->
          language = detect_language(validated_path)
          {:ok, content, language}
        
        {:error, reason} ->
          {:error, "Cannot read file: #{inspect(reason)}"}
      end
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, "File not found or is a directory"}
      _ -> {:error, "File too large (max 1MB)"}
    end
  end

  defp write_file_safely(path, content) do
    workspace_root = Workspaces.ensure_workspace_root!()
    
    case Cortex.Core.Security.validate_path_with_folders(path, workspace_root, []) do
      {:ok, validated_path} ->
        File.write(validated_path, content)
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp detect_language(path) do
    case Path.extname(path) do
      ".ex" -> "elixir"
      ".exs" -> "elixir"
      ".js" -> "javascript"
      ".ts" -> "typescript"
      ".jsx" -> "javascript"
      ".tsx" -> "typescript"
      ".md" -> "markdown"
      ".json" -> "json"
      ".yaml" -> "yaml"
      ".yml" -> "yaml"
      ".html" -> "html"
      ".heex" -> "html"
      ".eex" -> "html"
      ".css" -> "css"
      ".toml" -> "toml"
      ".rs" -> "rust"
      ".py" -> "python"
      ".rb" -> "ruby"
      ".go" -> "go"
      ".java" -> "java"
      ".c" -> "c"
      ".cpp" -> "cpp"
      ".h" -> "c"
      ".sh" -> "shell"
      ".bash" -> "shell"
      ".zsh" -> "shell"
      ".sql" -> "sql"
      ".xml" -> "xml"
      _ -> "plaintext"
    end
  end

  defp update_tab_content(tabs, path, new_content) do
    Enum.map(tabs, fn tab ->
      if tab.path == path do
        %{tab | content: new_content, dirty: tab.original_content != new_content}
      else
        tab
      end
    end)
  end

  defp update_tab_saved(tabs, path, content) do
    Enum.map(tabs, fn tab ->
      if tab.path == path do
        %{tab | content: content, original_content: content, dirty: false}
      else
        tab
      end
    end)
  end

  defp active_tab_content(tabs, active_path) do
    case Enum.find(tabs, fn tab -> tab.path == active_path end) do
      nil -> ""
      tab -> tab.content
    end
  end

  defp active_tab_language(tabs, active_path) do
    case Enum.find(tabs, fn tab -> tab.path == active_path end) do
      nil -> "plaintext"
      tab -> tab.language
    end
  end

  defp relative_path(path) do
    Path.relative_to_cwd(path)
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full bg-slate-950">
      <!-- Tab Bar -->
      <div class="flex items-center border-b border-slate-800 bg-slate-900 overflow-x-auto">
        <%= if @open_tabs == [] do %>
          <div class="px-4 py-2 text-sm text-slate-500">
            No files open
          </div>
        <% else %>
          <%= for tab <- @open_tabs do %>
            <div
              class={[
                "flex items-center gap-2 px-3 py-2 border-r border-slate-800 cursor-pointer transition-colors",
                if(@active_tab == tab.path, do: "bg-slate-950 text-white", else: "bg-slate-900 text-slate-400 hover:bg-slate-800")
              ]}
              phx-click="switch_tab"
              phx-value-path={tab.path}
              phx-target={@myself}
            >
              <span class="text-xs font-mono truncate max-w-[150px]" title={tab.path}>
                {Path.basename(tab.path)}
              </span>
              <%= if tab.dirty do %>
                <span class="text-orange-500">●</span>
              <% end %>
              <button
                class="hover:text-red-400 transition-colors"
                phx-click="close_tab"
                phx-value-path={tab.path}
                phx-target={@myself}
              >
                <.icon name="hero-x-mark" class="w-3 h-3" />
              </button>
            </div>
          <% end %>
        <% end %>
      </div>

      <!-- CodeMirror Editor -->
      <%= if @active_tab do %>
        <div 
          id="codemirror-editor"
          class="flex-1 overflow-hidden"
          phx-hook="CodeMirrorHook"
          phx-target={@myself}
          data-content={active_tab_content(@open_tabs, @active_tab)}
          data-language={active_tab_language(@open_tabs, @active_tab)}
        >
        </div>

        <!-- Status Bar -->
        <div class="flex items-center justify-between px-4 py-2 border-t border-slate-800 bg-slate-900 text-xs">
          <div class="flex items-center gap-4 text-slate-400">
            <span>{active_tab_language(@open_tabs, @active_tab)}</span>
            <span class={[
              if(@save_status == :unsaved, do: "text-orange-500", else: "text-slate-500")
            ]}>
              <%= if @save_status == :unsaved do %>
                ● Unsaved
              <% else %>
                Saved
              <% end %>
            </span>
          </div>

          <div class="flex items-center gap-2">
            <button
              class="px-3 py-1 bg-teal-600 hover:bg-teal-700 text-white rounded transition-colors"
              phx-click="inject_context"
              phx-target={@myself}
              title="Inject selected text or full file into chat context"
            >
              <.icon name="hero-arrow-up-tray" class="w-3 h-3 inline mr-1" />
              Inject Context
            </button>
            
            <button
              class="px-3 py-1 bg-slate-700 hover:bg-slate-600 text-white rounded transition-colors"
              phx-click="save_file"
              phx-target={@myself}
              phx-window-keydown="save_file"
              phx-key="s"
              phx-ctrl
              title="Save file (Ctrl+S)"
            >
              <.icon name="hero-document-check" class="w-3 h-3 inline mr-1" />
              Save
            </button>
          </div>
        </div>
      <% else %>
        <div class="flex-1 flex items-center justify-center text-slate-500">
          <div class="text-center">
            <.icon name="hero-document-text" class="w-16 h-16 mx-auto mb-4 opacity-50" />
            <p>No file selected</p>
            <p class="text-xs mt-2">Open a file from the file browser</p>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
