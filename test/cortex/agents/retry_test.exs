defmodule Cortex.Agents.RetryTest do
  use ExUnit.Case, async: true

  alias Cortex.Agents.Retry

  defmodule DummyError do
    defstruct [:status, :response_body]
  end

  test "classify_error handles non-String.Chars structs without crashing" do
    error =
      %DummyError{
        status: 403,
        response_body: %{"message" => "You have no permission to access this resource"}
      }

    assert Retry.classify_error(error) == :permanent
  end

  test "classify_error treats status 429 as transient" do
    error = %DummyError{status: 429, response_body: %{"message" => "rate limit exceeded"}}
    assert Retry.classify_error(error) == :transient
  end

  test "classify_error detects context overflow from response message" do
    error =
      %DummyError{
        status: 400,
        response_body: %{"message" => "prompt is too long for the context window"}
      }

    assert Retry.classify_error(error) == :context_overflow
  end

  test "user_message returns key invalid/permission denied hint for 403" do
    error =
      %DummyError{
        status: 403,
        response_body: %{"message" => "You have no permission to access this resource"}
      }

    assert Retry.user_message(error) =~ "Key 无效/权限不足"
  end
end
