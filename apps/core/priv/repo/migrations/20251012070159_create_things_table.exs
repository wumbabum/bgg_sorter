defmodule Core.Repo.Migrations.CreateThingsTable do
  use Ecto.Migration

  def change do
    create table(:things, primary_key: false) do
      add :id, :string, primary_key: true
      add :type, :string, null: false
      add :subtype, :string
      add :thumbnail, :string
      add :image, :string
      add :primary_name, :string
      add :description, :text
      add :yearpublished, :string
      add :minplayers, :string
      add :maxplayers, :string
      add :playingtime, :string
      add :minplaytime, :string
      add :maxplaytime, :string
      add :minage, :string
      add :usersrated, :string
      add :average, :string
      add :bayesaverage, :string
      add :rank, :string
      add :owned, :string
      add :averageweight, :string
      add :last_cached, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:things, [:last_cached])
    create index(:things, [:type])
    create index(:things, [:primary_name])
  end
end
