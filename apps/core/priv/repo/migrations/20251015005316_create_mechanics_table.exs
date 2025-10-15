defmodule Core.Repo.Migrations.CreateMechanicsTable do
  use Ecto.Migration

  def change do
    create table(:mechanics, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false

      timestamps(type: :utc_datetime)
    end

    # Unique indexes
    create unique_index(:mechanics, [:name])
    create unique_index(:mechanics, [:slug])
  end
end
