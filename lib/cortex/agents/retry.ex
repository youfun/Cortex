defmodule Cortex.Agents.Retry do
  @moduledoc """
  LLM 请求自动重试（指数退避）。

  错误分类：
  - :transient — 可重试（429、连接超时等）
  - :context_overflow — 需要压缩上下文而非重试
  - :permanent — 不可恢复（认证失败、无效请求等）
  """

  @max_retries 3
  @base_delay_ms 1000

  @type error_class :: :transient | :context_overflow | :permanent

  @doc "将错误分类为 transient / context_overflow / permanent"
  @spec classify_error(term()) :: error_class()
  def classify_error(error) do
    {status, error_str} = normalize_error(error)

    cond do
      status in [401, 403] ->
        :permanent

      status in [408, 425, 429, 500, 502, 503, 504] ->
        :transient

      context_overflow?(error_str) ->
        :context_overflow

      rate_limit?(error_str) ->
        :transient

      connection_error?(error_str) ->
        :transient

      is_integer(status) and status in 400..499 ->
        :permanent

      is_integer(status) and status in 500..599 ->
        :transient

      true ->
        :permanent
    end
  end

  @doc "将常见错误映射为用户可读提示（返回 nil 表示不特殊处理）"
  @spec user_message(term()) :: String.t() | nil
  def user_message(error) do
    {status, error_str} = normalize_error(error)

    cond do
      status in [401, 403] ->
        "Key 无效/权限不足，请检查 API Key 或访问权限"

      error_str =~ ~r/invalid api key|access_denied|permission denied|forbidden/i ->
        "Key 无效/权限不足，请检查 API Key 或访问权限"

      true ->
        nil
    end
  end

  @doc "是否应该重试"
  @spec should_retry?(error_class(), non_neg_integer()) :: boolean()
  def should_retry?(:transient, attempt) when attempt < @max_retries, do: true
  def should_retry?(_, _), do: false

  @doc "计算第 N 次重试的延迟毫秒数（指数退避）"
  @spec delay_ms(non_neg_integer()) :: non_neg_integer()
  def delay_ms(attempt) do
    trunc(@base_delay_ms * :math.pow(2, attempt))
  end

  @doc "返回最大重试次数"
  @spec max_retries() :: non_neg_integer()
  def max_retries, do: @max_retries

  @doc """
  执行带重试逻辑的任务。
  """
  @spec retry(
          fun :: (-> {:ok, term()} | {:error, term()}),
          on_retry :: (error_class(), non_neg_integer(), non_neg_integer() -> any()),
          attempt :: non_neg_integer()
        ) :: {:ok, term()} | {:error, term()}
  def retry(fun, on_retry \\ fn _, _, _ -> :ok end, attempt \\ 0) do
    case fun.() do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        class = classify_error(reason)

        if should_retry?(class, attempt) do
          delay = delay_ms(attempt)
          on_retry.(class, attempt, delay)
          Process.sleep(delay)
          retry(fun, on_retry, attempt + 1)
        else
          {:error, reason}
        end
    end
  end

  defp rate_limit?(str), do: str =~ ~r/429|rate.?limit/i
  defp connection_error?(str), do: str =~ ~r/connect|timeout|ECONNREFUSED|ETIMEDOUT/i

  defp context_overflow?(str) do
    str =~ ~r/too long|exceeds.*context|token.*exceed|maximum prompt|reduce.*length/i
  end

  defp normalize_error(error) do
    {extract_status(error), extract_message(error)}
  end

  defp extract_status(%{status: status}) when is_integer(status), do: status

  defp extract_status(%{response_body: %{"code" => code}}) when is_binary(code) do
    case Integer.parse(code) do
      {status, _} -> status
      :error -> nil
    end
  end

  defp extract_status(_), do: nil

  defp extract_message(error) when is_binary(error), do: error
  defp extract_message(error) when is_atom(error), do: Atom.to_string(error)

  defp extract_message(error) do
    cond do
      is_exception(error) ->
        Exception.message(error)

      is_map(error) and match?(%{response_body: %{}}, error) ->
        extract_message_from_response_body(error.response_body) || inspect(error)

      true ->
        inspect(error)
    end
  end

  defp extract_message_from_response_body(%{"message" => msg}) when is_binary(msg), do: msg
  defp extract_message_from_response_body(%{"error" => msg}) when is_binary(msg), do: msg
  defp extract_message_from_response_body(%{"detail" => msg}) when is_binary(msg), do: msg
  defp extract_message_from_response_body(_), do: nil
end
