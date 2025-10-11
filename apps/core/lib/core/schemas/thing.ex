defmodule Core.Schemas.Thing do
  @moduledoc """
  Schema representing detailed BoardGameGeek thing information.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: String.t(),
          type: String.t(),
          subtype: String.t() | nil,
          thumbnail: String.t() | nil,
          image: String.t() | nil,
          primary_name: String.t() | nil,
          description: String.t() | nil,
          yearpublished: String.t() | nil,
          minplayers: String.t() | nil,
          maxplayers: String.t() | nil,
          playingtime: String.t() | nil,
          minplaytime: String.t() | nil,
          maxplaytime: String.t() | nil,
          minage: String.t() | nil,
          usersrated: String.t() | nil,
          average: String.t() | nil,
          bayesaverage: String.t() | nil,
          rank: String.t() | nil,
          owned: String.t() | nil,
          averageweight: String.t() | nil
        }

  @primary_key false
  embedded_schema do
    field :id, :string
    field :type, :string
    field :subtype, :string
    field :thumbnail, :string
    field :image, :string
    field :primary_name, :string
    field :description, :string
    field :yearpublished, :string
    field :minplayers, :string
    field :maxplayers, :string
    field :playingtime, :string
    field :minplaytime, :string
    field :maxplaytime, :string
    field :minage, :string
    field :usersrated, :string
    field :average, :string
    field :bayesaverage, :string
    field :rank, :string
    field :owned, :string
    field :averageweight, :string
  end

  @required_fields ~w(id type)a
  @optional_fields ~w(subtype thumbnail image primary_name description yearpublished minplayers maxplayers playingtime minplaytime maxplaytime minage usersrated average bayesaverage rank owned averageweight)a

  @doc "Generates a changeset for the Thing schema."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(thing \\ %__MODULE__{}, params) do
    thing
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
