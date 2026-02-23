defmodule Mix.Tasks.Jido.Gen.Channel do
  use Mix.Task
  import Mix.Generator

  @shortdoc "Generates a new SNS channel adapter skeleton"

  @moduledoc """
  Generates a new SNS channel adapter skeleton.

      mix jido.gen.channel telegram
  """

  @impl true
  def run([name]) do
    app = Mix.Project.config()[:app] |> to_string()
    base = "lib/#{app}/channels/#{name}"
    mod = name |> Macro.camelize()

    create_directory(base)

    create_file("#{base}/adapter.ex", adapter_template(app, mod, name))
    create_file("#{base}/client.ex", client_template(app, mod))
    create_file("#{base}/dispatcher.ex", dispatcher_template(app, mod, name))
    create_file("#{base}/receiver.ex", receiver_template(app, mod, name))
    create_file("#{base}/supervisor.ex", supervisor_template(app, mod))

    Mix.shell().info("Channel adapter generated in #{base}")

    Mix.shell().info(
      "Remember to add #{app_module(app)}.Channels.#{mod}.Adapter to :channel_adapters"
    )
  end

  def run(_args) do
    Mix.raise("usage: mix jido.gen.channel <name>")
  end

  defp app_module(app) do
    app |> Macro.camelize()
  end

  defp adapter_template(app, mod, name) do
    """
    defmodule #{app_module(app)}.Channels.#{mod}.Adapter do
      @moduledoc \"\"\"
      #{mod} channel adapter metadata and child specs.
      \"\"\"
      @behaviour #{app_module(app)}.Channel.Adapter

      @impl true
      def channel, do: \"#{name}\"

      @impl true
      def enabled? do
        cfg = Application.get_env(:#{app}, :#{name}, [])
        api_key = cfg[:api_key]
        is_binary(api_key) and api_key != \"\"
      end

      @impl true
      def child_specs do
        [
          #{app_module(app)}.Channels.#{mod}.Receiver,
          #{app_module(app)}.Channels.#{mod}.Dispatcher
        ]
      end

      @impl true
      def config do
        Application.get_env(:#{app}, :#{name}, [])
      end
    end
    """
  end

  defp client_template(app, mod) do
    """
    defmodule #{app_module(app)}.Channels.#{mod}.Client do
      @moduledoc \"\"\"
      #{mod} API client based on Req.
      \"\"\"
      require Logger

      def new do
        Req.new()
      end
    end
    """
  end

  defp dispatcher_template(app, mod, name) do
    """
    defmodule #{app_module(app)}.Channels.#{mod}.Dispatcher do
      @moduledoc \"\"\"
      #{mod} outbound dispatcher.
      \"\"\"
      use GenServer
      require Logger
      alias #{app_module(app)}.SignalHub

      def start_link(opts \\\\ []) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @impl true
      def init(_opts) do
        SignalHub.subscribe(\"jido.#{name}.cmd.*\")
        {:ok, %{}}
      end

      @impl true
      def handle_info(msg, state) do
        Logger.debug(\"[#{mod}.Dispatcher] Received: \#{inspect(msg)}\")
        {:noreply, state}
      end
    end
    """
  end

  defp receiver_template(app, mod, name) do
    """
    defmodule #{app_module(app)}.Channels.#{mod}.Receiver do
      @moduledoc \"\"\"
      #{mod} inbound receiver.
      \"\"\"
      use GenServer
      require Logger
      alias #{app_module(app)}.SignalHub

      def start_link(opts \\\\ []) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @impl true
      def init(_opts) do
        SignalHub.subscribe(\"#{name}.message.text\")
        {:ok, %{}}
      end

      @impl true
      def handle_info(msg, state) do
        Logger.debug(\"[#{mod}.Receiver] Received: \#{inspect(msg)}\")
        {:noreply, state}
      end
    end
    """
  end

  defp supervisor_template(app, mod) do
    """
    defmodule #{app_module(app)}.Channels.#{mod}.Supervisor do
      @moduledoc \"\"\"
      #{mod} channel supervision tree.
      \"\"\"
      use Supervisor

      def start_link(opts \\\\ []) do
        Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @impl true
      def init(_opts) do
        children = [
          #{app_module(app)}.Channels.#{mod}.Receiver,
          #{app_module(app)}.Channels.#{mod}.Dispatcher
        ]

        Supervisor.init(children, strategy: :one_for_one)
      end
    end
    """
  end
end
