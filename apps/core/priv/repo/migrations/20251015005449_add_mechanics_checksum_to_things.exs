defmodule Core.Repo.Migrations.AddMechanicsChecksumToThings do
  use Ecto.Migration

  def change do
    alter table(:things) do
      add :mechanics_checksum, :string
    end

    create index(:things, [:mechanics_checksum])
  end
end
