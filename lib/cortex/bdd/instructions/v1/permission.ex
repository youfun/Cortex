defmodule Cortex.BDD.Instructions.V1.Permission do
  @moduledoc false

  import ExUnit.Assertions

  alias Cortex.BDD.Instructions.V1.Helpers
  alias Cortex.Core.PermissionTracker
  alias Cortex.Tools.ShellInterceptor

  @spec capabilities() :: MapSet.t(atom())
  def capabilities do
    MapSet.new([
      :check_permission,
      :resolve_permission_request,
      :assert_authorized,
      :check_shell_command,
      :assert_approval_required
    ])
  end

  def run(ctx, kind, name, args) do
    case {kind, name} do
      {:when, :check_permission} ->
        session_id = Map.get(args, :session_id) || Map.get(ctx, :session_id, "bdd_session")

        PermissionTracker.check_permission(args.actor, args.action, %{
          session_id: session_id,
          context: args.context
        })

        {:ok, ctx}

      {:when, :resolve_permission_request} ->
        decision = Helpers.parse_decision_atom(args.decision)
        duration = Helpers.parse_duration_atom(Map.get(args, :duration, "once"))

        resolution =
          case {decision, duration} do
            {:allow, :once} -> :allow_once
            {:allow, :always} -> :allow_always
            {:deny, _} -> :deny
          end

        PermissionTracker.resolve_request(args.request_id, resolution)
        {:ok, ctx}

      {:then, :assert_authorized} ->
        _session_id = Map.get(args, :session_id) || Map.get(ctx, :session_id, "bdd_session")
        authorized = PermissionTracker.authorized?(args.actor, args.action)

        assert authorized == args.expected,
               "Expected authorization for #{args.actor} to #{args.action} to be #{args.expected}, but got #{authorized}"

        {:ok, ctx}

      {:when, :check_shell_command} ->
        result = ShellInterceptor.check(args.command)
        {:ok, Map.put(ctx, :last_shell_check, result)}

      {:then, :assert_approval_required} ->
        last_result = Map.get(ctx, :last_shell_check)

        if args.required do
          assert match?({:approval_required, _}, last_result),
                 "Expected approval required, but got: #{inspect(last_result)}"

          if args.reason do
            {:approval_required, reason} = last_result

            assert reason =~ args.reason,
                   "Expected approval reason to contain '#{args.reason}', but got: '#{reason}'"
          end
        else
          assert last_result == :ok,
                 "Expected command to be allowed, but got: #{inspect(last_result)}"
        end

        {:ok, ctx}

      _ ->
        :no_match
    end
  end
end
