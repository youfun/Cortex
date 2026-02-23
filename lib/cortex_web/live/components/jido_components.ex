defmodule CortexWeb.JidoComponents do
  @moduledoc """
  Functional components for the Cortex UI.
  
  This module serves as an aggregation entry point that imports all sub-components.
  """
  use CortexWeb, :html

  # Re-export all functions from sub-modules
  defdelegate chat_panel(assigns), to: CortexWeb.JidoComponents.ChatPanel
  defdelegate agents_panel(assigns), to: CortexWeb.JidoComponents.AgentsPanel
  defdelegate add_folder_modal(assigns), to: CortexWeb.JidoComponents.Modals
  defdelegate archived_conversations_modal(assigns), to: CortexWeb.JidoComponents.Modals
  defdelegate permission_modal(assigns), to: CortexWeb.JidoComponents.Modals
end
