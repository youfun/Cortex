# Extension Lifecycle - HookRegistry Tests

defmodule Cortex.Extensions.HookRegistryTest do
  use ExUnit.Case, async: false

  alias Cortex.Extensions.HookRegistry

  setup do
    # Start the registry if not already started
    case Process.whereis(HookRegistry) do
      nil -> start_supervised!(HookRegistry)
      _pid -> :ok
    end

    :ok
  end

  describe "register_global/1" do
    test "registers a global hook" do
      defmodule TestHook1 do
        @behaviour Cortex.Agents.Hook
      end

      assert :ok = HookRegistry.register_global(TestHook1)
      hooks = HookRegistry.get_hooks("any_session")
      assert TestHook1 in hooks
    end
  end

  describe "register_session/2" do
    test "registers a session-specific hook" do
      defmodule TestHook2 do
        @behaviour Cortex.Agents.Hook
      end

      assert :ok = HookRegistry.register_session("session_123", TestHook2)
      hooks = HookRegistry.get_hooks("session_123")
      assert TestHook2 in hooks
    end
  end

  describe "get_hooks/1" do
    test "returns global + session hooks" do
      defmodule TestHook3 do
        @behaviour Cortex.Agents.Hook
      end

      defmodule TestHook4 do
        @behaviour Cortex.Agents.Hook
      end

      HookRegistry.register_global(TestHook3)
      HookRegistry.register_session("session_456", TestHook4)

      hooks = HookRegistry.get_hooks("session_456")
      assert TestHook3 in hooks
      assert TestHook4 in hooks
    end
  end

  describe "unregister/1" do
    test "removes hook from all registrations" do
      defmodule TestHook5 do
        @behaviour Cortex.Agents.Hook
      end

      HookRegistry.register_global(TestHook5)
      HookRegistry.register_session("session_789", TestHook5)

      assert :ok = HookRegistry.unregister(TestHook5)

      hooks_global = HookRegistry.get_hooks("any_session")
      hooks_session = HookRegistry.get_hooks("session_789")

      refute TestHook5 in hooks_global
      refute TestHook5 in hooks_session
    end
  end
end
