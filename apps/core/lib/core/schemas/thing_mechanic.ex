defmodule Core.Schemas.ThingMechanic do
  @moduledoc """
  Join table schema connecting Things and Mechanics.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "thing_mechanics" do
    belongs_to :thing, Core.Schemas.Thing, type: :string
    belongs_to :mechanic, Core.Schemas.Mechanic, type: :binary_id

    # Insert-only
    timestamps(type: :utc_datetime, updated_at: false)
  end

  @required_fields ~w(thing_id mechanic_id)a
  @optional_fields ~w()a

  @doc "Generates a changeset for the ThingMechanic schema."
  def changeset(thing_mechanic \\ %__MODULE__{}, params) do
    thing_mechanic
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:thing_id, :mechanic_id],
      name: "thing_mechanics_thing_id_mechanic_id_index"
    )
    |> foreign_key_constraint(:thing_id)
    |> foreign_key_constraint(:mechanic_id)
  end

  @doc "Query for finding all ThingMechanics for a given thing ID."
  def for_thing(query \\ __MODULE__, thing_id) do
    import Ecto.Query
    from tm in query, where: tm.thing_id == ^thing_id
  end
end
