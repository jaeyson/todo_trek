defmodule TodoTrek.ActivityLog do
  @moduledoc """
  Defines a basic activity log for decoupled activity streams.

  > This module is *not intended for use as a forensic log* of
  events. It does not provide transactional guarantees and cannot
  be used to recreate state in a system, such as a full event source
  or similar log.
  """
  import Ecto.Query
  alias TodoTrek.ActivityLog
  alias TodoTrek.ActivityLog.Entry
  alias TodoTrek.{Repo, ReplicaRepo, Scope, Todos}

  def build(%Scope{} = scope, %Todos.Todo{} = todo, %{} = attrs) do
    scope
    |> build_changeset(todo, attrs)
    |> Ecto.Changeset.apply_changes()
    |> Map.take([
      :meta,
      :action,
      :performer_text,
      :subject_text,
      :before_text,
      :after_text,
      :todo_id,
      :list_id,
      :user_id,
      :inserted_at,
      :updated_at
    ])
  end

  def log(%Scope{} = scope, %Todos.Todo{} = todo, %{} = attrs) do
    scope
    |> build_changeset(todo, attrs)
    |> Repo.insert!()
  end

  def log(%Scope{} = scope, %Todos.List{} = list, %{} = attrs) do
    id = if list.__meta__.state == :deleted, do: nil, else: list.id

    %Entry{list_id: id, user_id: scope.current_user_id}
    |> put_performer(scope)
    |> Entry.changeset(attrs)
    |> Repo.insert!()
  end

  def list_user_logs(%Scope{} = scope, opts) do
    limit = Keyword.fetch!(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    from(l in ActivityLog.Entry,
      where: l.user_id == ^scope.current_user.id,
      offset: ^offset,
      limit: ^limit,
      order_by: [desc: l.id]
    )
    |> ReplicaRepo.all()
  end

  defp put_performer(%Entry{} = entry, %Scope{} = scope) do
    %Entry{entry | performer_text: scope.current_user.email}
  end

  defp build_changeset(scope, todo, attrs) do
    id = if todo.__meta__.state == :deleted, do: nil, else: todo.id
    now = DateTime.utc_now(:second)

    %Entry{
      todo_id: id,
      list_id: todo.list_id,
      user_id: scope.current_user_id,
      inserted_at: now,
      updated_at: now
    }
    |> put_performer(scope)
    |> Entry.changeset(attrs)
  end
end
