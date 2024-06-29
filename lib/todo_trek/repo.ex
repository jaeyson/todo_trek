defmodule TodoTrek.Repo do
  use Ecto.Repo,
    otp_app: :todo_trek,
    adapter: Ecto.Adapters.Postgres

  import Ecto.Query

  def stale(as_of \\ 5000, func) when is_integer(as_of) do
    {:ok, result} =
      transaction(fn ->
        query!("set transaction read only", [])
        query!("set yb_read_from_followers = true", [])
        query!("set yb_follower_read_staleness_ms = #{as_of}", [])
        func.()
      end)

    result
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

  def retryable_transaction(fun_or_multi, retries \\ 10, sleep \\ 2) do
    try do
      transaction(fun_or_multi)
    catch
      :error, %Postgrex.Error{postgres: %{code: code}} = err
      when code in [:serialization_failure, :lock_not_available] ->
        if retries > 0 do
          Process.sleep(sleep)
          IO.puts("Retrying rescued transaction, retries left: #{retries - 1}")
          retryable_transaction(fun_or_multi, retries - 1, sleep * 2)
        else
          reraise(err, __STACKTRACE__)
        end
    end
  end
end

defmodule TodoTrek.ReplicaRepo do
  use Ecto.Repo,
    otp_app: :todo_trek,
    adapter: Ecto.Adapters.Postgres

  require Logger

  def set_follower_reads(conn) do
    Logger.info("Setting follower reads #{System.get_env("FLY_REGION")} #{inspect(node())}")
    Postgrex.query!(conn, "set session characteristics as transaction read only;", [])
    Postgrex.query!(conn, "set yb_read_from_followers = true;", [])
    Postgrex.query!(conn, "set yb_follower_read_staleness_ms = 5000;", [])

    for tab <- ~w(users todos lists) do
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
    end
  end
end
