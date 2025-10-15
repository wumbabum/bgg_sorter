defmodule Core.Repo.Migrations.CreateThingMechanicsTable do
  use Ecto.Migration

  def change do
    create table(:thing_mechanics, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :thing_id, references(:things, type: :string, on_delete: :delete_all), null: false

      add :mechanic_id, references(:mechanics, type: :binary_id, on_delete: :delete_all),
        null: false

      add :inserted_at, :utc_datetime, null: false
    end

    # Composite unique index to prevent duplicate thing-mechanic pairs
    create unique_index(:thing_mechanics, [:thing_id, :mechanic_id])

    # Performance indexes for lookups
    create index(:thing_mechanics, [:thing_id])
    create index(:thing_mechanics, [:mechanic_id])
  end
end
