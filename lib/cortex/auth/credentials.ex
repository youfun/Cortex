defmodule Cortex.Auth.Credentials do
  @moduledoc """
  管理各种 AI Agent 的认证凭据。

  支持从以下来源读取凭证：
  - 环境变量
  - GitHub CLI (`gh auth token`)
  - GitHub Copilot 配置文件
  - 系统配置文件
  """
  require Logger

  @doc """
  获取 GitHub Copilot 的认证令牌。

  按优先级尝试以下来源：
  1. 环境变量（GITHUB_COPILOT_TOKEN, GH_TOKEN, GITHUB_TOKEN）
  2. `gh auth token` 命令输出
  3. GitHub Copilot 配置文件（~/.config/github-copilot/hosts.json）
  """
  def get_github_token do
    env_keys = [
      "GITHUB_COPILOT_TOKEN",
      "GH_TOKEN",
      "GITHUB_TOKEN",
      "COPILOT_GITHUB_TOKEN"
    ]

    # 1. 尝试环境变量
    # 2. 尝试 gh CLI
    # 3. 尝试配置文件
    Enum.find_value(env_keys, fn key ->
      case System.get_env(key) do
        nil -> nil
        "" -> nil
        token -> {:ok, token}
      end
    end) ||
      get_token_from_gh_cli() ||
      get_token_from_copilot_config() ||
      {:error, :github_token_not_found}
  end

  @doc """
  获取 Google Gemini 的 API Key（可选）。

  注意：Gemini CLI 支持预先登录（类似 GitHub Copilot），
  因此 API Key 是可选的。如果用户已通过 `gemini login` 登录，
  则无需提供 API Key。

  按优先级尝试：
  1. 环境变量（GEMINI_API_KEY, GOOGLE_API_KEY）
  2. Gemini CLI 配置文件（~/.gemini/config.json）
  3. 返回 nil（允许 CLI 使用已登录的凭证）
  """
  def get_gemini_api_key do
    env_keys = ["GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_GEMINI_API_KEY"]

    # 不再返回错误，而是返回 nil，让 CLI 使用已登录的凭证
    Enum.find_value(env_keys, fn key ->
      case System.get_env(key) do
        nil -> nil
        "" -> nil
        key_val -> {:ok, key_val}
      end
    end) ||
      get_gemini_key_from_config() ||
      nil
  end

  # -- Private Helpers --

  defp get_token_from_gh_cli do
    case System.cmd("gh", ["auth", "token"], stderr_to_stdout: true) do
      {output, 0} ->
        token = String.trim(output)

        if token != "" and not String.contains?(token, "not logged") do
          Logger.info("Successfully retrieved GitHub token from gh CLI")
          {:ok, token}
        else
          nil
        end

      {error, _code} ->
        Logger.debug("gh CLI not available or not logged in: #{error}")
        nil
    end
  end

  defp get_token_from_copilot_config do
    config_path = copilot_config_path()

    if File.exists?(config_path) do
      case File.read(config_path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, %{"github.com" => %{"oauth_token" => token}}} when is_binary(token) ->
              Logger.info("Successfully retrieved GitHub token from copilot config")
              {:ok, token}

            {:ok, data} ->
              Logger.debug(
                "Copilot config exists but missing oauth_token: #{inspect(Map.keys(data))}"
              )

              nil

            {:error, reason} ->
              Logger.warning("Failed to parse copilot config: #{inspect(reason)}")
              nil
          end

        {:error, reason} ->
          Logger.debug("Failed to read copilot config: #{inspect(reason)}")
          nil
      end
    else
      Logger.debug("Copilot config not found at: #{config_path}")
      nil
    end
  end

  defp copilot_config_path do
    config_dir =
      case :os.type() do
        {:win32, _} ->
          # Windows: %USERPROFILE%\.config\github-copilot
          userprofile = System.get_env("USERPROFILE") || System.get_env("HOME")
          Path.join([userprofile, ".config", "github-copilot"])

        _ ->
          # Unix: ~/.config/github-copilot
          home = System.get_env("HOME")
          Path.join([home, ".config", "github-copilot"])
      end

    Path.join(config_dir, "hosts.json")
  end

  defp get_gemini_key_from_config do
    config_path = gemini_config_path()

    if File.exists?(config_path) do
      case File.read(config_path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, %{"api_key" => key}} when is_binary(key) ->
              Logger.info("Successfully retrieved Gemini API key from config")
              {:ok, key}

            {:ok, %{"apiKey" => key}} when is_binary(key) ->
              {:ok, key}

            _ ->
              nil
          end

        {:error, _reason} ->
          nil
      end
    else
      nil
    end
  end

  defp gemini_config_path do
    case :os.type() do
      {:win32, _} ->
        userprofile = System.get_env("USERPROFILE") || System.get_env("HOME")
        Path.join([userprofile, ".gemini", "config.json"])

      _ ->
        home = System.get_env("HOME")
        Path.join([home, ".gemini", "config.json"])
    end
  end

  @doc """
  为指定的 Agent 准备环境变量。

  ## 认证策略

  - **GitHub Copilot**: 优先使用环境变量/gh CLI/配置文件的 token，
    若都不可用则返回空环境变量，让 CLI 自己处理认证。
    
  - **Gemini**: 优先使用环境变量/配置文件的 API Key，
    若不可用则返回空环境变量，依赖用户提前执行 `gemini login`。
    
  - **Qwen**: 无需认证。

  ## Examples
      
      iex> Cortex.Auth.Credentials.prepare_env("github-copilot")
      {:ok, [{"GITHUB_COPILOT_TOKEN", "gho_xxxxx"}]}
      
      iex> Cortex.Auth.Credentials.prepare_env("gemini")
      {:ok, []}  # 依赖 `gemini login`
  """
  def prepare_env("github-copilot") do
    case get_github_token() do
      {:ok, token} ->
        Logger.info("Using GitHub token from credentials manager")
        {:ok, [{"GITHUB_COPILOT_TOKEN", token}]}

      {:error, reason} ->
        Logger.info("No GitHub token found (#{inspect(reason)}), relying on CLI authentication")
        # 返回空环境变量，让 CLI 自己尝试认证
        {:ok, []}
    end
  end

  def prepare_env("gemini") do
    case get_gemini_api_key() do
      {:ok, key} ->
        Logger.info("Using Gemini API key from credentials manager")
        {:ok, [{"GEMINI_API_KEY", key}]}

      nil ->
        Logger.info("No Gemini API key found, relying on `gemini login` authentication")
        # 依赖用户提前执行 `gemini login`
        {:ok, []}
    end
  end

  def prepare_env("qwen") do
    # Qwen Code 目前不需要认证
    {:ok, []}
  end

  def prepare_env(_agent_id) do
    {:ok, []}
  end
end
