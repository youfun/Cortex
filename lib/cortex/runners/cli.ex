defmodule Cortex.Runners.CLI do
  @moduledoc """
  外部 Agent CLI Runner。

  通过 Port 启动外部 CLI 进程（gemini / claude / codex 等），
  发送 prompt，收集输出，返回结果。

  ## Options

  - `:cli`     — (必需) CLI 二进制名，如 `"gemini"`, `"claude"`, `"codex"`
  - `:cwd`     — 工作目录，传给 CLI 的 --cwd 参数
  - `:timeout` — 超时毫秒数，默认 120_000
  - `:env`     — 额外环境变量 `[{"KEY", "VALUE"}]`
  """

  @behaviour Cortex.Runners.Runner

  require Logger

  @default_timeout 120_000

  @impl true
  def run(prompt, opts) do
    cli = Keyword.fetch!(opts, :cli)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    case System.find_executable(cli) do
      nil ->
        {:error, {:cli_not_found, cli}}

      binary ->
        args = build_args(cli, prompt, opts)
        env = Keyword.get(opts, :env, [])
        run_port(binary, args, env, timeout)
    end
  end

  @impl true
  def available?(opts) do
    cli = Keyword.get(opts, :cli, "")
    System.find_executable(cli) != nil
  end

  @impl true
  def info(opts) do
    cli = Keyword.get(opts, :cli, "unknown")

    %{
      id: cli,
      name: cli_display_name(cli),
      type: :cli,
      cost: :free
    }
  end

  # ── 各 CLI 的命令参数构建 ──

  defp build_args("gemini", prompt, opts) do
    cwd = Keyword.get(opts, :cwd)
    base = ["-p", prompt]

    if cwd,
      do: Enum.reverse([cwd, "--cwd" | Enum.reverse(base)]),
      else: base
  end

  defp build_args("claude", prompt, opts) do
    cwd = Keyword.get(opts, :cwd)
    base = ["--print", "--dangerously-skip-permissions", "-p", prompt]
    if cwd, do: ["--cwd", cwd | base], else: base
  end

  defp build_args("codex", prompt, opts) do
    cwd = Keyword.get(opts, :cwd)
    base = ["--quiet", "-p", prompt]
    if cwd, do: ["--cwd", cwd | base], else: base
  end

  defp build_args(_cli, prompt, _opts) do
    # 通用 fallback：直接传 prompt 作为参数
    [prompt]
  end

  # ── Port 执行 ──

  defp run_port(binary, args, env, timeout) do
    port_opts = [:binary, :exit_status, :stderr_to_stdout, {:args, args}]
    port_opts = if env != [], do: [{:env, env} | port_opts], else: port_opts

    port = Port.open({:spawn_executable, binary}, port_opts)
    collect_output(port, timeout, [])
  end

  defp collect_output(port, timeout, acc) do
    receive do
      {^port, {:data, data}} ->
        collect_output(port, timeout, [data | acc])

      {^port, {:exit_status, 0}} ->
        {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary()}

      {^port, {:exit_status, code}} ->
        output = acc |> Enum.reverse() |> IO.iodata_to_binary()
        {:error, {:exit_code, code, String.slice(output, 0, 2000)}}
    after
      timeout ->
        safe_close_port(port)
        {:error, :timeout}
    end
  end

  defp safe_close_port(port), do: Port.close(port)

  # ── 显示名 ──

  defp cli_display_name("gemini"), do: "Gemini CLI"
  defp cli_display_name("claude"), do: "Claude Code"
  defp cli_display_name("codex"), do: "Codex"
  defp cli_display_name(other), do: other
end
