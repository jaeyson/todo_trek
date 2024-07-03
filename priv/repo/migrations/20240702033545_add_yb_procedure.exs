defmodule TodoTrek.Repo.Migrations.AddYbProcedure do
  use Ecto.Migration

  def change do
    execute """
    CREATE OR REPLACE FUNCTION set_yb_read_stale(staleness_ms integer) RETURNS void AS $$
    BEGIN
        SET yb_read_from_followers = true;
        SET TRANSACTION READ ONLY;
        EXECUTE 'SET yb_follower_read_staleness_ms = ' || staleness_ms;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE OR REPLACE FUNCTION warmup_yb_metadata() RETURNS void AS $$
    BEGIN
        -- Query pg_yb_tablegroup
        PERFORM 1 FROM pg_yb_tablegroup WHERE 1 = 0;

        -- Query pg_yb_catalog_version
        PERFORM 1 FROM pg_yb_catalog_version WHERE 1 = 0;

        -- Query pg_yb_profile
        PERFORM 1 FROM pg_yb_profile WHERE 1 = 0;

        -- Query pg_yb_migration
        PERFORM 1 FROM pg_yb_migration WHERE 1 = 0;

        -- Query pg_yb_role_profile
        PERFORM 1 FROM pg_yb_role_profile WHERE 1 = 0;
    END;
    $$ LANGUAGE plpgsql;
    """
  end
end
