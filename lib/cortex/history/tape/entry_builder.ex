defmodule Cortex.History.Tape.EntryBuilder do
  @moduledoc """
  Tape Entry 构建器。
  
  提供便捷函数将不同类型的事件转换为标准的 Tape.Entry 结构。
  """

  alias Cortex.History.Tape

  @doc """
  构建消息类型的 Entry。
  """
  def message(role, content, opts \\ []) do
    session_id = Keyword.get(opts, :session_id)
    
    %Tape.Entry{
      seq_id: generate_seq_id(),
      kind: :message,
      payload: %{
        "role" => role,
        "content" => content
      },
      meta: %{
        "session_id" => session_id,
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }
  end

  @doc """
  构建工具调用类型的 Entry。
  """
  def tool_call(tool_calls, opts \\ []) do
    session_id = Keyword.get(opts, :session_id)
    
    %Tape.Entry{
      seq_id: generate_seq_id(),
      kind: :tool_call,
      payload: %{
        "tool_calls" => tool_calls
      },
      meta: %{
        "session_id" => session_id,
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }
  end

  @doc """
  构建工具结果类型的 Entry。
  """
  def tool_result(tool_name, call_id, status, output, opts \\ []) do
    session_id = Keyword.get(opts, :session_id)
    elapsed_ms = Keyword.get(opts, :elapsed_ms)
    
    %Tape.Entry{
      seq_id: generate_seq_id(),
      kind: :tool_result,
      payload: %{
        "tool_name" => tool_name,
        "call_id" => call_id,
        "status" => status,
        "output" => output
      },
      meta: %{
        "session_id" => session_id,
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "elapsed_ms" => elapsed_ms
      }
    }
  end

  @doc """
  构建系统事件类型的 Entry。
  """
  def system(event_type, data, opts \\ []) do
    session_id = Keyword.get(opts, :session_id)
    
    %Tape.Entry{
      seq_id: generate_seq_id(),
      kind: :system,
      payload: %{
        "event_type" => event_type,
        "data" => data
      },
      meta: %{
        "session_id" => session_id,
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }
  end

  @doc """
  构建 anchor 类型的 Entry（检查点）。
  """
  def anchor(name, state, opts \\ []) do
    session_id = Keyword.get(opts, :session_id)
    
    %Tape.Entry{
      seq_id: generate_seq_id(),
      kind: :anchor,
      payload: %{
        "name" => name,
        "state" => state
      },
      meta: %{
        "session_id" => session_id,
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }
  end

  # Private Helpers

  defp generate_seq_id do
    System.unique_integer([:positive, :monotonic])
  end
end
