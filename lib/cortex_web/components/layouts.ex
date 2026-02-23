defmodule CortexWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use CortexWeb, :html

  # Embed all files in layouts/* within this module.
  embed_templates "layouts/*"

  @doc """
  Renders a navigation item for the sidebar.
  """
  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  def nav_item(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "group relative p-3 rounded-xl transition-all duration-200",
        @active && "bg-teal-600/10 text-teal-400",
        !@active && "text-slate-400 hover:bg-slate-800 hover:text-white"
      ]}
    >
      <.icon name={@icon} class="w-6 h-6" />
      <span class="absolute left-14 px-2 py-1 bg-slate-800 text-white text-xs rounded opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap pointer-events-none z-50">
        {@label}
      </span>
      <div
        :if={@active}
        class="absolute -left-0.5 top-1/4 bottom-1/4 w-1 bg-teal-500 rounded-r-full"
      />
    </.link>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Renders the sidebar navigation with logo and navigation items.
  """
  attr :active_tab, :atom, required: true

  def sidebar(assigns) do
    ~H"""
    <div class="w-16 flex flex-col items-center py-4 bg-slate-950 border-r border-slate-800 space-y-4 h-full flex-shrink-0">
      <%!-- Logo --%>
      <div class="w-10 h-10 bg-teal-600 rounded-lg flex items-center justify-center mb-4 shadow-lg shadow-teal-500/20">
        <span class="text-white font-bold text-xl">J</span>
      </div>

      <%!-- Navigation Items --%>
      <.nav_item
        href="/"
        icon="hero-chat-bubble-left-right"
        label="Chat"
        active={@active_tab == :chat}
      />

      <%!-- <.nav_item
        href="/providers"
        icon="hero-server"
        label="Providers"
        active={@active_tab == :providers}
      /> --%>

      <.nav_item
        href="/models"
        icon="hero-cpu-chip"
        label="Models"
        active={@active_tab == :models}
      />

      <.nav_item
        href="/settings/channels"
        icon="hero-cog-6-tooth"
        label="Settings"
        active={@active_tab == :settings or @active_tab == :providers}
      />

      <%!-- Spacer --%>
      <div class="flex-1"></div>

      <%!-- Quit Button --%>
      <button
        phx-click="shutdown"
        data-confirm="Are you sure you want to quit Cortex?"
        class="group relative p-3 rounded-xl transition-all duration-200 text-slate-400 hover:bg-red-600/10 hover:text-red-400"
      >
        <.icon name="hero-power" class="w-6 h-6" />
        <span class="absolute left-14 px-2 py-1 bg-slate-800 text-white text-xs rounded opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap pointer-events-none z-50">
          Quit
        </span>
      </button>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
