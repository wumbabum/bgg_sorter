defmodule Core.Schemas.Mechanic do
  @moduledoc """
  Schema representing BoardGameGeek mechanics.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "mechanics" do
    field :name, :string
    field :slug, :string

    # Associations
    has_many :thing_mechanics, Core.Schemas.ThingMechanic
    many_to_many :things, Core.Schemas.Thing, join_through: Core.Schemas.ThingMechanic

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(name slug)a
  @optional_fields ~w()a

  @doc "Generates a changeset for the Mechanic schema."
  def changeset(mechanic \\ %__MODULE__{}, params) do
    mechanic
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:name)
    |> unique_constraint(:slug)
  end

  @doc "Generates URL-friendly slug from mechanic name"
  def generate_slug(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s\-]/, "")
    |> String.replace(~r/[\s\-]+/, "-")
    |> String.trim("-")
  end

  @doc "Gets the most popular mechanics ordered by usage count"
  def most_popular(limit \\ 20) do
    from(m in __MODULE__,
      join: tm in assoc(m, :thing_mechanics),
      group_by: [m.id, m.name, m.slug],
      order_by: [desc: count(tm.thing_id)],
      select: m,
      limit: ^limit
    )
  end
end
