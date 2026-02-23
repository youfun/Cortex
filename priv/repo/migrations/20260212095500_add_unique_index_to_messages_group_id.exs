defmodule Cortex.Repo.Migrations.AddUniqueIndexToMessagesGroupId do
  use Ecto.Migration

  def change do
    create unique_index(:messages, [:group_id])
  end
end
