defmodule TodoTrek.Todos do
  @moduledoc """
  The Todos context.
  """

  import Ecto.Query, warn: false
  alias TodoTrek.{Repo, ReplicaRepo, Scope, Events}

  alias TodoTrek.Todos.{List, Todo}
  alias TodoTrek.ActivityLog

  @max_todos_per_list 100

  @doc """
  Subscribers the given scope to the todo pubsub.

  For logged in users, this will be a topic scoped only to the logged in user.
  If the system is extended to allow shared lists, the topic subscription could
  be derived for a particular organization or team, particular list, and so on.
  """
  def subscribe(%Scope{} = scope) do
    Phoenix.PubSub.subscribe(TodoTrek.PubSub, topic(scope))
  end

  @doc """
  Reorders a list in the current users board.

  Broadcasts `%Events.ListRepositioned{}` on the scoped topic when successful.
  """
  def update_list_position(%Scope{} = scope, list_id, new_index) when is_binary(list_id) do
    Repo.transact(fn ->
      {list, _locked_user_id} =
        Repo.one!(
          from l in List,
            where: l.id == ^list_id and l.user_id == ^scope.current_user.id,
            join: u in assoc(l, :user),
            on: u.id == l.user_id,
            limit: 1,
            select: {l, u.id},
            preload: [:todos],
            lock: "FOR UPDATE"
        )

      {:ok, new_index} = reposition(list, new_index, user_id: scope.current_user.id)
      new_list = %List{list | position: new_index}

      log =
        ActivityLog.log(scope, list, %{
          action: "list_position_updated",
          subject_text: list.title,
          before_text: list.position,
          after_text: new_index
        })

      {:ok, {new_list, log}}
    end)
    |> case do
      {:ok, {new_list, log}} ->
        broadcast(scope, %Events.ListRepositioned{list: new_list, log: log})
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Updates the position of a todo in the list it belongs to.

  Broadcasts %Events.TodoRepositioned{} on the scoped topic.
  """
  def update_todo_position(%Scope{} = scope, todo_id, list_id, new_index)
      when is_binary(todo_id) and is_binary(list_id) do
    Repo.transact(fn ->
      # lock todo and list, and enforce todo still belongs to list
      {todo, list} =
        Repo.one!(
          from t in Todo,
            where:
              t.id == ^todo_id and t.list_id == ^list_id and
                t.user_id == ^scope.current_user.id,
            join: l in assoc(t, :list),
            on: l.id == t.list_id,
            where: l.user_id == ^scope.current_user.id,
            select: {t, l},
            limit: 1,
            lock: "FOR UPDATE"
        )

      {:ok, new_index} = reposition(todo, new_index, list_id: list.id)

      log =
        ActivityLog.log(scope, todo, %{
          action: "todo_position_updated",
          subject_text: todo.title,
          before_text: todo.position,
          after_text: new_index
        })

      new_todo = %Todo{todo | position: new_index}

      {:ok, {new_todo, todo, log}}
    end)
    |> case do
      {:ok, {new_todo, old_todo, log}} ->
        broadcast(scope, %Events.TodoRepositioned{todo: new_todo, old_todo: old_todo, log: log})
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def change_todo(todo_or_changeset, attrs \\ %{}) do
    Todo.changeset(todo_or_changeset, attrs)
  end

  @doc """
  Moves a todo from one list to another.

  Broadcasts %Events.TodoDeleted{} on the scoped topic for the old list.
  Broadcasts %Events.TodoRepositioned{} on the scoped topic for the new list.
  """
  def move_todo_to_list(%Scope{} = scope, todo_id, old_list_id, new_list_id, at_index)
      when is_binary(old_list_id) and is_binary(new_list_id) and old_list_id != new_list_id do
    Repo.transact(fn ->
      {todo, old_list} =
        Repo.one!(
          from t in Todo,
            where:
              t.id == ^todo_id and t.list_id == ^old_list_id and
                t.user_id == ^scope.current_user.id,
            join: l in assoc(t, :list),
            on: l.id == t.list_id,
            where: l.user_id == ^scope.current_user.id,
            select: {t, l},
            limit: 1,
            lock: "FOR UPDATE"
        )

      {new_list, pos_at_end} =
        Repo.one!(
          from(l in List,
            where: l.id == ^new_list_id and l.user_id == ^scope.current_user.id,
            select:
              {l, subquery(from t in Todo, where: t.list_id == ^new_list_id, select: count(t.id))},
            limit: 1,
            lock: "FOR UPDATE"
          )
        )

      # decrement positions in old list
      {_, _} = Repo.update_all(decrement_positions_query(todo, list_id: old_list.id), [])
      # move todo to end of new list
      {1, _} =
        Repo.update_all(
          from(t in Todo,
            where: t.id == ^todo.id,
            update: [set: [list_id: ^new_list.id, position: ^pos_at_end]]
          ),
          []
        )

      # reposition in new list
      {:ok, new_index} = reposition(todo, at_index, list_id: new_list.id)

      # bump values
      new_todo = %Todo{todo | list: new_list, list_id: new_list.id, position: new_index}

      # log activity
      log =
        ActivityLog.log(scope, new_todo, %{
          action: "todo_moved",
          subject_text: new_todo.title,
          before_text: old_list.title,
          after_text: new_list.title
        })

      {:ok, {new_todo, todo, log}}
    end)
    |> case do
      {:ok, {new_todo, old_todo, log}} ->
        broadcast(scope, %Events.TodoRepositioned{todo: new_todo, old_todo: old_todo, log: log})
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes a todo for the current scope.

  Broadcasts %Events.TodoDeleted{} on the scoped topic when successful.
  """
  def delete_todo(%Scope{} = scope, todo_id, list_id)
      when is_binary(todo_id) and is_binary(list_id) do
    Repo.transact(fn ->
      # locks todo and list
      todo_lock_query =
        from(t in Todo,
          where:
            t.id == ^todo_id and t.user_id == ^scope.current_user.id and
              t.list_id == ^list_id,
          join: l in assoc(t, :list),
          where: l.user_id == ^scope.current_user.id,
          select: {t, l},
          lock: "FOR UPDATE",
          limit: 1
        )

      with {%Todo{} = todo, %List{} = list} <- Repo.one(todo_lock_query),
           {_, _} <- Repo.update_all(decrement_positions_query(todo, list_id: list.id), []),
           {:ok, deleted_todo} <- Repo.delete(todo) do
        log =
          ActivityLog.log(scope, deleted_todo, %{
            action: "todo_deleted",
            subject_text: deleted_todo.title
          })

        broadcast(scope, %Events.TodoDeleted{todo: todo, log: log})
        {:ok, todo}
      else
        _ -> {:error, :not_found}
      end
    end)
  end

  @doc """
  Lists todos for the current scope.
  """
  def list_todos(%Scope{} = scope, limit) do
    Repo.all(
      from(t in Todo,
        where: t.user_id == ^scope.current_user.id,
        limit: ^limit,
        order_by: [asc: :position]
      )
    )
  end

  @doc """
  Updates a todo as completed for the current scope.

  Broadcasts %Events.TodoToggled{} on the scoped topic when successful.
  """
  def mark_completed(%Scope{} = scope, todo_id) when is_binary(todo_id) do
    toggle_status(scope, todo_id, :completed)
  end

  @doc """
  Updates a todo as started for the current scope.

  Broadcasts %Events.TodoToggled{} on the scoped topic when successful.
  """
  def mark_started(%Scope{} = scope, todo_id) when is_binary(todo_id) do
    toggle_status(scope, todo_id, :started)
  end

  defp toggle_status(%Scope{} = scope, todo_id, new_status)
       when is_binary(todo_id) and new_status in [:completed, :started] do
    old_status = if new_status == :completed, do: :started, else: :completed

    Repo.transact(fn ->
      update_query =
        from(t in Todo,
          where: t.id == ^todo_id and t.user_id == ^scope.current_user.id,
          update: [set: [status: ^new_status]],
          select: t
        )

      with {1, [new_todo]} <- Repo.update_all(update_query, []) do
        log =
          ActivityLog.log(scope, new_todo, %{
            action: "todo_toggled",
            subject_text: new_todo.title,
            before_text: old_status,
            after_text: new_todo.status
          })

        broadcast(scope, %Events.TodoToggled{todo: new_todo, log: log})
        {:ok, new_todo}
      end
    end)
  end

  def get_todo!(%Scope{} = scope, id) do
    ReplicaRepo.stale(scope, fn repo ->
      from(t in Todo, where: t.id == ^id and t.user_id == ^scope.current_user.id)
      |> repo.one!()
      |> repo.preload(:list)
    end)
  end

  @doc """
  Updates a todo for the current scope.

  Broadcasts %Events.TodoUpdated{} on the scoped topic when successful.
  """
  def update_todo(%Scope{} = scope, %Todo{} = todo, params) do
    # Process.sleep(1000)
    todo
    |> Todo.changeset(params)
    |> Repo.update()
    |> case do
      {:ok, new_todo} ->
        log =
          if todo.title != new_todo.title do
            ActivityLog.log(scope, new_todo, %{
              action: "todo_updated",
              subject_text: todo.title,
              after_text: new_todo.title
            })
          end

        broadcast(scope, %Events.TodoUpdated{todo: new_todo, log: log})

        {:ok, new_todo}

      other ->
        other
    end
  end

  def bulk_create_todos(%Scope{} = scope, list_id, todos) do
    # TODO there is a race here across concurrent transactions. Event with the lock
    # the order of the end-user submitting the transaction can race others.
    # The lock itself works in that positions are updated properly, but the
    # order the user added the todos is not guaranteed to match.
    Ecto.Multi.new()
    |> Ecto.Multi.run(:list, fn repo, _changes ->
      todos_count = length(todos)

      {current_count, title} =
        Repo.one!(
          from(l in List,
            where: l.id == ^list_id and l.user_id == ^scope.current_user.id,
            select:
              {subquery(from t in Todo, where: t.list_id == ^list_id, select: count(t.id)),
               l.title},
            lock: "FOR UPDATE"
          )
        )

      if current_count + todos_count > @max_todos_per_list do
        {:error, :list_full}
      else
        now = DateTime.utc_now(:second)

        todos =
          for {todo, i} <- Enum.with_index(todos) do
            todo
            |> Map.put_new_lazy(:id, &Ecto.UUID.generate/0)
            |> Map.merge(%{
              user_id: scope.current_user.id,
              status: :started,
              inserted_at: now,
              updated_at: now,
              list_id: list_id,
              position: current_count + i
            })
          end

        {^todos_count, inserted_todos} = repo.insert_all(Todo, todos, returning: true)

        {:ok, {current_count + todos_count, title, inserted_todos}}
      end
    end)
    |> Ecto.Multi.run(:log, fn repo, %{list: {_count, title, todos}} ->
      {logs, todos_map} =
        Enum.reduce(todos, {[], %{}}, fn todo, {logs, todos_map} ->
          log =
            ActivityLog.build(scope, todo, %{
              action: "todo_created",
              subject_text: todo.title,
              after_text: title
            })

          {[log | logs], Map.put(todos_map, todo.id, todo)}
        end)

      logs = Enum.reverse(logs)
      logs_count = length(logs)
      {^logs_count, logs} = repo.insert_all(ActivityLog.Entry, logs, returning: true)

      {:ok, {logs, todos_map}}
    end)
    |> Repo.transact()
    |> case do
      {:ok, %{list: {_count, _title, todos}, log: {logs, todos_map}}} ->
        for log <- logs, todo = Map.fetch!(todos_map, log.todo_id) do
          broadcast(scope, %Events.TodoAdded{todo: todo, log: log})
        end

        {:ok, todos}

      {:error, step, value, _changes_so_far} ->
        {:error, {step, value}}
    end
  end

  @doc """
  Creates a todo for the current scope.

  Broadcasts %Events.TodoAdded{} on the scoped topic when successful.
  """
  def create_todo(%Scope{} = scope, list_id, todo_id \\ Ecto.UUID.generate(), params)
      when is_binary(list_id) do
    todo = %Todo{
      id: todo_id,
      user_id: scope.current_user.id,
      status: :started,
      list_id: list_id
    }

    changeset = Todo.changeset(todo, params)

    if changeset.valid? do
      todo_map =
        changeset
        |> Ecto.Changeset.apply_changes()
        |> Todo.to_map()
        |> Map.take([:id, :user_id, :status, :list_id, :title, :position])

      case bulk_create_todos(scope, list_id, [todo_map]) do
        {:ok, [todo]} -> {:ok, todo}
        {:error, :list_full} -> {:error, :list_full}
        {:error, {step, value}} -> {:error, {step, value}}
      end
    else
      {:error, changeset}
    end
  end

  @doc """
  Returns the active lists for the current scope.
  """
  def active_lists(%Scope{} = scope, limit) do
    ReplicaRepo.stale(scope, fn repo ->
      lists =
        from(l in List,
          where: l.user_id == ^scope.current_user.id,
          limit: ^limit,
          order_by: [asc: :position]
        )
        |> repo.all()

      repo.preload(lists,
        todos:
          from(t in Todo,
            where: t.user_id == ^scope.current_user.id,
            limit: ^(Enum.count(lists) * @max_todos_per_list),
            order_by: [asc: t.position]
          )
      )
    end)
  end

  @doc """
  Gets a single list owned by the scoped user.

  Raises `Ecto.NoResultsError` if the List does not exist.
  """
  def get_list!(%Scope{} = scope, id) do
    ReplicaRepo.stale(scope, fn repo ->
      from(l in List, where: l.user_id == ^scope.current_user.id, where: l.id == ^id)
      |> repo.one!()
      |> repo.preload([:todos])
    end)
  end

  @doc """
  Creates a list for the current scope.

  Broadcasts `%Events.ListAdded{}` on the scoped topic when successful.
  """
  def create_list(%Scope{} = scope, attrs \\ %{}) do
    Ecto.Multi.new()
    |> Repo.multi_lock_for_update(:user_lock, [scope.current_user])
    |> Ecto.Multi.run(:position, fn repo, _changes ->
      position =
        repo.one(from l in List, where: l.user_id == ^scope.current_user.id, select: count(l.id))

      {:ok, position}
    end)
    |> Ecto.Multi.insert(:list, fn %{position: position} ->
      List.changeset(%List{user_id: scope.current_user.id, position: position}, attrs)
    end)
    |> Ecto.Multi.run(:log, fn _repo, %{list: list} ->
      log =
        ActivityLog.log(scope, list, %{
          action: "list_created",
          subject_text: list.title
        })

      {:ok, log}
    end)
    |> Repo.transact()
    |> case do
      {:ok, %{list: list, log: log}} ->
        list = Repo.preload(list, :todos)
        broadcast(scope, %Events.ListAdded{list: list, log: log})

        {:ok, list}

      {:error, _failed_op, failed_val, _changes_so_far} ->
        {:error, failed_val}
    end
  end

  @doc """
  Updates a list.

  Broadcasts %Events.ListUpdated{} on the scoped topic when successful.
  """
  def update_list(%Scope{} = scope, %List{} = list, attrs) do
    list
    |> List.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, new_list} ->
        log =
          if list.title != new_list.title do
            ActivityLog.log(scope, new_list, %{
              action: "list_updated",
              subject_text: list.title,
              after_text: new_list.title
            })
          end

        broadcast(scope, %Events.ListUpdated{list: new_list, log: log})

        {:ok, new_list}

      other ->
        other
    end
  end

  @doc """
  Deletes a list.

  Broadcasts %Events.ListDeleted{} on the scoped topic when successful.
  """
  def delete_list(%Scope{} = scope, list_id) when is_binary(list_id) do
    user_id = scope.current_user.id

    Repo.transact(fn ->
      # locks list and current user
      {%List{} = list, _locked_user_id} =
        Repo.one(
          from(l in List,
            where: l.id == ^list_id and l.user_id == ^user_id,
            join: u in assoc(l, :user),
            on: u.id == l.user_id,
            select: {l, u.id},
            lock: "FOR UPDATE",
            limit: 1
          )
        )

      log =
        ActivityLog.log(scope, list, %{
          action: "list_deleted",
          subject_text: list.title
        })

      with {_, _} <- Repo.update_all(decrement_positions_query(list, user_id: user_id), []),
           {:ok, deleted_list} <- Repo.delete(list) do
        broadcast(scope, %Events.ListDeleted{list: list, log: log})
        {:ok, deleted_list}
      else
        _ -> {:error, :not_found}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking list changes.

  ## Examples

      iex> change_list(list)
      %Ecto.Changeset{data: %List{}}

  """
  def change_list(%List{} = list, attrs \\ %{}) do
    List.changeset(list, attrs)
  end

  defp broadcast(%Scope{} = scope, event) do
    Phoenix.PubSub.broadcast(TodoTrek.PubSub, topic(scope), {__MODULE__, event})
  end

  defp topic(%Scope{} = scope), do: "todos:#{scope.current_user.id}"

  defp decrement_positions_query(%type{} = struct, where_query) do
    from(t in type,
      where: ^where_query,
      where:
        t.position > subquery(from og in type, where: og.id == ^struct.id, select: og.position),
      update: [inc: [position: -1]]
    )
  end

  defp reposition(%type{} = struct, new_idx, where_query) when is_integer(new_idx) do
    old_position = from(og in type, where: og.id == ^struct.id, select: og.position)

    computed_index =
      case Repo.one(from(t in type, where: ^where_query, select: count(t.id))) do
        count when new_idx < count -> new_idx
        count -> count - 1
      end

    # decrement positions of items after old position and before new position
    {_, _} =
      Repo.update_all(
        from(t in type,
          where: ^where_query,
          where: t.id != ^struct.id,
          where: t.position > subquery(old_position) and t.position <= ^computed_index,
          update: [inc: [position: -1]]
        ),
        []
      )

    # increment positions of items after new position and before old position
    {_, _} =
      Repo.update_all(
        from(t in type,
          where: ^where_query,
          where: t.id != ^struct.id,
          where: t.position < subquery(old_position) and t.position >= ^computed_index,
          update: [inc: [position: 1]]
        ),
        []
      )

    {_, _} =
      Repo.update_all(
        from(t in type,
          where: t.id == ^struct.id,
          update: [set: [position: ^computed_index]]
        ),
        []
      )

    {:ok, computed_index}
  end
end
