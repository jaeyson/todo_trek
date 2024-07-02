defmodule TodoTrek.Repo.Migrations.AddMissingIndexes do
  use Ecto.Migration

  def change do
    create index(:todos, [:position])
    create index(:lists, [:position])
    create index(:activity_log_entries, [:user_id, :inserted_at])
  end
end
