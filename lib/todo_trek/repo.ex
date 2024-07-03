defmodule TodoTrek.Repo do
  use Ecto.Repo,
    otp_app: :todo_trek,
    adapter: Ecto.Adapters.Postgres

  require Logger
  import Ecto.Query

  def transact(multi_or_func, opts \\ [])

  def transact(%Ecto.Multi{} = multi, opts) do
    TodoTrek.RPC.rpc_primary(fn ->
      retryable_transaction(multi, opts)
    end)
  end

  def transact(func, opts) when is_function(func, 0) do
    TodoTrek.RPC.rpc_primary(fn ->
      retryable_transaction(
        fn ->
          case func.() do
            {:ok, value} -> value
            :ok -> :transaction_commited
            {:error, reason} -> rollback(reason)
            :error -> rollback(:transaction_rollback_error)
          end
        end,
        opts
      )
    end)
  end

  def multi_lock_for_update(multi, lock_name, [%schema{} | _] = schemas)
      when is_atom(lock_name) and is_list(schemas) do
    ids = for schema <- schemas, do: schema.id

    Ecto.Multi.run(multi, lock_name, fn repo, _changes ->
      ids =
        repo.all(from(s in schema, where: s.id in ^ids, select: s.id, lock: "FOR UPDATE NOWAIT"))

      {:ok, ids}
    end)
  end

  def multi_lock_for_update(multi, lock_name, {schema, ids})
      when is_atom(lock_name) and is_atom(schema) and is_list(ids) do
    Ecto.Multi.run(multi, lock_name, fn repo, _changes ->
      ids = repo.all(from(s in schema, where: s.id in ^ids, select: s.id, lock: "FOR UPDATE"))
      {:ok, ids}
    end)
  end

  def retryable_transaction(fun_or_multi, opts \\ [], retries \\ 10, sleep \\ 2) do
    try do
      transaction(fun_or_multi, opts)
    catch
      :error, %Postgrex.Error{postgres: %{code: code}} = err
      when code in [:serialization_failure, :lock_not_available] ->
        if retries > 0 do
          Process.sleep(sleep)
          IO.puts("Retrying rescued transaction, retries left: #{retries - 1}")
          retryable_transaction(fun_or_multi, opts, retries - 1, sleep * 2)
        else
          reraise(err, __STACKTRACE__)
        end
    end
  end

  def warmup(conn) do
    Logger.info("Warmup #{System.get_env("FLY_REGION")} #{inspect(node())}")

    for tab <- ~w(users todos lists activity_log_entries) do
      # Fetch basic table information
      Postgrex.query!(conn, "SELECT relname, relkind FROM pg_class WHERE relname = '#{tab}';", [])
      # Fetch column information
      Postgrex.query!(
        conn,
        "SELECT attname, atttypid FROM pg_attribute WHERE attrelid = '#{tab}'::regclass;",
        []
      )

      # Fetch statistics information
      Postgrex.query!(
        conn,
        "SELECT starelid, stanullfrac FROM pg_statistic WHERE starelid = '#{tab}'::regclass;",
        []
      )

      # Fetch index information for the table
      Postgrex.query!(
        conn,
        "SELECT indexrelid, indrelid FROM pg_index WHERE indrelid = '#{tab}'::regclass;",
        []
      )

      # Fetch trigger information
      Postgrex.query!(
        conn,
        "SELECT tgname, tgtype FROM pg_trigger WHERE tgrelid = '#{tab}'::regclass;",
        []
      )

      # Run an EXPLAIN to prefetch query plan information
      Postgrex.query!(conn, "EXPLAIN SELECT * FROM #{tab} WHERE 1 = 0;", [])
      # Run a simple query to load data into cache
      Postgrex.query!(conn, "SELECT * FROM #{tab} LIMIT 1;", [])

      # Distributed queries to ensure cluster nodes are warmed up
      Postgrex.query!(conn, "SELECT * FROM #{tab} WHERE id IS NULL;", [])
    end

    # Call the yb warm-up function
    Postgrex.query!(conn, "SELECT warmup_yb_metadata();", [])
  end
end

defmodule TodoTrek.ReplicaRepo do
  use Ecto.Repo,
    otp_app: :todo_trek,
    adapter: Ecto.Adapters.Postgres,
    read_only: true

  require Logger

  def set_follower_reads(conn) do
    TodoTrek.Repo.warmup(conn)
    Logger.info("Setting follower reads #{System.get_env("FLY_REGION")} #{inspect(node())}")
    Postgrex.query!(conn, "set yb_read_from_followers = true;", [])
    Postgrex.query!(conn, "set session characteristics as transaction read only;", [])
    Postgrex.query!(conn, "set yb_follower_read_staleness_ms = 5000;", [])
  end

  def stale(%TodoTrek.Scope{} = scope, func) do
    stale(scope.last_side_effect_at, func)
  end

  def stale(as_of_ms_time_ago, func)
      when is_integer(as_of_ms_time_ago) or is_nil(as_of_ms_time_ago) do
    now = System.system_time(:millisecond)
    as_of_ms_time_ago = as_of_ms_time_ago || now - 30_000
    staleness_ms = now - as_of_ms_time_ago
    staleness_ms = if staleness_ms > 30_000, do: 30_000, else: staleness_ms

    if staleness_ms < 2_000 do
      func.(TodoTrek.Repo)
    else
      checkout(fn ->
        query!("SELECT set_yb_read_stale($1);", [staleness_ms])
        func.(TodoTrek.ReplicaRepo)
      end)
    end
  end
end
