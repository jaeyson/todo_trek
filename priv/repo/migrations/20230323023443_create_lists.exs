defmodule TodoTrek.Repo.Migrations.CreateLists do
  use Ecto.Migration

  def change do
    create table(:lists, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :title, :string
      add :user_id, references(:users, on_delete: :delete_all, type: :uuid)
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:lists, [:user_id])
  end
end
