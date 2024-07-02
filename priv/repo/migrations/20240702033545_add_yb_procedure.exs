defmodule TodoTrek.Repo.Migrations.AddYbProcedure do
  use Ecto.Migration

  def change do
    execute """
    CREATE OR REPLACE FUNCTION set_yb_read_stale(staleness_ms integer) RETURNS void AS $$
    BEGIN
        SET LOCAL yb_read_from_followers = true;
        SET LOCAL TRANSACTION READ ONLY;
        EXECUTE 'SET LOCAL yb_follower_read_staleness_ms = ' || staleness_ms;
    END;
    $$ LANGUAGE plpgsql;
    """
  end
end
