---
name: beam-remote-debug
description: Remote debugging for BEAM/Elixir in production-like environments. Use when you need to enter a live container or host via kubectl exec or ssh to run IEx/remote RPC, reproduce issues, and collect telemetry/metrics safely with human-in-the-loop approval.
---

# BEAM Remote Debug Skill

Use this skill to safely debug a running BEAM system by attaching with IEx or running remote RPC, then capture state, telemetry, and metrics without destabilizing production.

## Guardrails

- Confirm you have explicit approval for any production access or risky commands.
- Prefer read-only inspection first; avoid writes or destructive operations.
- Do not trigger cascading signals from signal callbacks; read operations should not emit signals.
- Log what you did and what you found in a short report under `docs/`.

## Inputs to Collect

- Environment: `prod` or `staging`
- Target: namespace, deployment/release, pod, container
- Access: `ssh` (VPS) or `docker exec` (container on VPS)
- App name and release bin path: `/app/bin/<app>` or similar

## Determine Deployment Type

Use a quick check to decide whether this is a native release on the VPS or a Dockerized deployment.

Native release (VPS):
- `/app/bin/<app>` exists on the host
- `systemctl status <app>` shows a running service
- No matching container in `docker ps`

Docker deployment (VPS):
- `docker ps` shows a container for the app
- The release lives inside the container at `/app/bin/<app>` or `/opt/<app>/bin/<app>`

## Standard Workflow

1. Identify target host or container
2. Attach with `ssh` or `docker exec`
3. Start IEx remote or use RPC
4. Reproduce and collect state
5. Summarize findings and next steps in `docs/<date>-beam-remote-debug.md`

## Command Templates

VPS host discovery (your inventory/source of truth):

```bash
ssh <user>@<host>
```

Docker container discovery (on VPS):

```bash
docker ps
docker ps --filter "name=<app>"
```

Docker exec shell:

```bash
docker exec -it <container> /bin/sh
```

IEx remote (release, inside host or container):

```bash
/app/bin/<app> remote
```

RPC one-liner (release):

```bash
/app/bin/<app> rpc "<Elixir expression>"
```

SSH to host:

```bash
ssh <user>@<host>
```

## Safe Introspection Examples

Use these in IEx or via `rpc` to collect state safely.

```elixir
:erlang.memory()
:erlang.statistics(:run_queue)
Process.list() |> length()
Process.whereis(<registered_name>)
Process.info(<pid>, [:message_queue_len, :memory, :current_function])
:sys.get_state(<pid>)
:sys.statistics(<pid>, true)
```

## Telemetry and Metrics Checklist

- List telemetry handlers and check for duplicates
- Capture key counters and histograms relevant to the incident
- Record queue lengths, memory, and scheduler stats

Suggested collection (adjust to your system):

```elixir
:telemetry.list_handlers([])
:erlang.statistics(:scheduler_wall_time)
:erlang.statistics(:io)
```

## Reporting Template

Create `docs/<date>-beam-remote-debug.md` with:

- Context: incident description and time range
- Access method: kubectl exec or ssh, target pod/host
- Commands run (with redacted secrets)
- Observations: state, metrics, and anomalies
- Hypothesis and proposed fix
- Follow-ups or monitoring changes

## Notes

- If you need to run code across components, prefer sending signals via SignalHub rather than direct cross-component calls.
- Keep IEx sessions focused and short; exit cleanly when done.
