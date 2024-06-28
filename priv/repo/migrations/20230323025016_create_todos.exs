defmodule TodoTrek.Repo.Migrations.CreateTodos do
  use Ecto.Migration

  def change do
    create table(:todos, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :title, :string
      add :status, :string
      add :position, :integer, null: false
      add :list_id, references(:lists, on_delete: :nothing, type: :uuid)
      add :user_id, references(:users, on_delete: :delete_all, type: :uuid)

      timestamps(type: :utc_datetime)
    end

    create index(:todos, [:list_id])
    create index(:todos, [:user_id])
  end
end
