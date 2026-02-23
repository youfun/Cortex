defmodule Cortex.Repo do
  use Ecto.Repo,
    otp_app: :cortex,
    adapter: Ecto.Adapters.SQLite3
end
