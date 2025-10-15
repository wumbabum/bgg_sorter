defmodule Core.Repo.Migrations.AddSchemaVersioningToThings do
  use Ecto.Migration

  def change do
    # Add schema_version column with default value 2 for new records
    alter table(:things) do
      add :schema_version, :integer, default: 2
    end

    # Add index on schema_version for query performance
    create index(:things, [:schema_version])

    # Backfill existing records with schema_version 1 (pre-mechanics)
    execute(
      "UPDATE things SET schema_version = 1 WHERE schema_version IS NULL;",
      "UPDATE things SET schema_version = NULL WHERE schema_version = 1;"
    )
  end
end
