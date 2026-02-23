defmodule Cortex.Test.MockLLM do
  use Plug.Router
  require Logger

  plug :match
  plug :dispatch

  # 使用 Agent 存储 session_id -> file_name 的映射
  def start_link do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  defp get_file_name(session_id, content) do
    # 1. 尝试从内容中提取
    case Regex.run(~r/integration_test_test_loop_\d+\.txt/i, content) do
      [name] ->
        Agent.update(__MODULE__, &Map.put(&1, session_id, name))
        name

      _ ->
        # 2. 尝试从 Agent 缓存中读取
        Agent.get(__MODULE__, &Map.get(&1, session_id, "integration_test.txt"))
    end
  end

  post "/v1/chat/completions" do
    {:ok, body, _conn} = Plug.Conn.read_body(conn)
    decoded = Jason.decode!(body)
    messages = decoded["messages"]
    last_message = List.last(messages)
    content = last_message["content"]

    # 从历史消息中寻找 session_id 标识
    # 遍历所有消息寻找包含 test_loop_ 的内容
    session_id =
      Enum.find_value(messages, "default_session", fn msg ->
        content = msg["content"] || ""

        case Regex.run(~r/test_loop_\d+/, content) do
          [id] -> id
          _ -> nil
        end
      end)

    file_name = get_file_name(session_id, content)

    Logger.debug(
      "[MockLLM] Session: #{session_id}, Content: #{String.slice(content, 0..50)}, File: #{file_name}"
    )

    # 构造响应消息
    response_msg =
      cond do
        String.contains?(content, "步骤") or String.contains?(content, "创建") ->
          %{
            "content" => "I will create the file for you.",
            "tool_calls" => [
              %{
                "index" => 0,
                "id" => "call_123",
                "type" => "function",
                "function" => %{
                  "name" => "shell",
                  "arguments" => Jason.encode!(%{command: "echo 'Jido Loop Test' > #{file_name}"})
                }
              }
            ]
          }

        String.contains?(content, "Exit code: 0") ->
          if String.contains?(content, "read_file") do
            %{
              "content" => "I have verified the content. COMPLETED_SUCCESSFULLY"
            }
          else
            %{
              "content" => "File created. Now reading it.",
              "tool_calls" => [
                %{
                  "index" => 0,
                  "id" => "call_456",
                  "type" => "function",
                  "function" => %{
                    "name" => "read_file",
                    "arguments" => Jason.encode!(%{path: file_name})
                  }
                }
              ]
            }
          end

        true ->
          %{
            "content" => "I received your message: #{content}. COMPLETED_SUCCESSFULLY"
          }
      end

    # 发送 SSE 响应
    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> send_chunked(200)

    # 发送第一块：角色
    chunk1 = %{
      id: "chatcmpl-mock",
      object: "chat.completion.chunk",
      created: System.system_time(:second),
      model: decoded["model"],
      choices: [%{index: 0, delta: %{role: "assistant"}, finish_reason: nil}]
    }

    {:ok, conn} = chunk(conn, "data: #{Jason.encode!(chunk1)}\n\n")

    # 发送内容
    conn =
      if Map.has_key?(response_msg, "content") do
        chunk_content = %{
          id: "chatcmpl-mock",
          object: "chat.completion.chunk",
          created: System.system_time(:second),
          model: decoded["model"],
          choices: [%{index: 0, delta: %{content: response_msg["content"]}, finish_reason: nil}]
        }

        {:ok, conn} = chunk(conn, "data: #{Jason.encode!(chunk_content)}\n\n")
        conn
      else
        conn
      end

    # 发送工具调用（分片）
    if Map.has_key?(response_msg, "tool_calls") do
      Enum.each(response_msg["tool_calls"], fn tc ->
        # 1. 发送 ID 和 Name
        tc_chunk1 = %{
          id: "chatcmpl-mock",
          object: "chat.completion.chunk",
          created: System.system_time(:second),
          model: decoded["model"],
          choices: [
            %{
              index: 0,
              delta: %{
                tool_calls: [
                  %{
                    index: tc["index"],
                    id: tc["id"],
                    type: "function",
                    function: %{name: tc["function"]["name"], arguments: ""}
                  }
                ]
              },
              finish_reason: nil
            }
          ]
        }

        chunk(conn, "data: #{Jason.encode!(tc_chunk1)}\n\n")

        # 2. 发送参数
        tc_chunk2 = %{
          id: "chatcmpl-mock",
          object: "chat.completion.chunk",
          created: System.system_time(:second),
          model: decoded["model"],
          choices: [
            %{
              index: 0,
              delta: %{
                tool_calls: [
                  %{
                    index: tc["index"],
                    function: %{arguments: tc["function"]["arguments"]}
                  }
                ]
              },
              finish_reason: nil
            }
          ]
        }

        chunk(conn, "data: #{Jason.encode!(tc_chunk2)}\n\n")
      end)
    end

    # 发送结束标志
    last_chunk = %{
      id: "chatcmpl-mock",
      object: "chat.completion.chunk",
      created: System.system_time(:second),
      model: decoded["model"],
      choices: [
        %{
          index: 0,
          delta: %{},
          finish_reason:
            if(Map.has_key?(response_msg, "tool_calls"), do: "tool_calls", else: "stop")
        }
      ]
    }

    {:ok, conn} = chunk(conn, "data: #{Jason.encode!(last_chunk)}\n\n")
    {:ok, conn} = chunk(conn, "data: [DONE]\n\n")
    conn
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end
end
