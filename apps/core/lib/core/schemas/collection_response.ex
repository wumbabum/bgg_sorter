defmodule Core.Schemas.CollectionResponse do
  @moduledoc """
  Schema representing a BoardGameGeek collection response.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Core.Schemas.Thing

  @type t :: %__MODULE__{
          totalitems: String.t() | nil,
          termsofuse: String.t() | nil,
          items: [Thing.t()]
        }

  @primary_key false
  embedded_schema do
    field :totalitems, :string
    field :termsofuse, :string
    embeds_many :items, Thing
  end

  @required_fields ~w()a
  @optional_fields ~w(totalitems termsofuse)a

  @doc "Generates a changeset for the CollectionResponse schema."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(collection \\ %__MODULE__{}, params) do
    collection
    |> cast(params, @required_fields ++ @optional_fields)
    |> cast_embed(:items, with: &Thing.changeset/2)
    |> validate_required(@required_fields)
  end
end
