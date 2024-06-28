defmodule TodoTrek.Todos.Todo do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "todos" do
    field :status, Ecto.Enum, values: [:started, :completed], default: :started
    field :title, :string
    field :position, :integer

    belongs_to :list, TodoTrek.Todos.List, type: :binary_id
    belongs_to :user, TodoTrek.Accounts.User, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def to_map(%__MODULE__{} = todo) do
    Map.take(todo, [
      :id,
      :title,
      :status,
      :position,
      :user_id,
      :list_id,
      :inserted_at,
      :updated_at
    ])
  end

  @doc false
  def changeset(todo, attrs) do
    todo
    |> cast(attrs, [:id, :title, :status])
    |> validate_required([:title])
    |> validate_inclusion(:status, [:started, :completed])
  end
end
