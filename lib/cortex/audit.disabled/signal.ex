defmodule Cortex.Audit.Signal do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "signals" do
    field :source, :string
    field :type, :string
    field :data, :map
    field :occurred_at, :utc_datetime
    field :conversation_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(signal, attrs) do
    signal
    |> cast(attrs, [:source, :type, :data, :occurred_at])
    |> validate_required([:source, :type, :occurred_at])
  end
end
