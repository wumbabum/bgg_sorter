defmodule Core.Schemas.CollectionResponse do
  @moduledoc """
  Schema representing a BoardGameGeek collection response.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          items: [map()]
        }

  @primary_key false
  embedded_schema do
    field :items, {:array, :map}
  end

  @required_fields ~w()a
  @optional_fields ~w(items)a

  @doc "Generates a changeset for the CollectionResponse schema."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(collection \\ %__MODULE__{}, params) do
    collection
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_items()
  end

  # Custom validation for items as maps
  defp validate_items(changeset) do
    case get_change(changeset, :items) do
      items when is_list(items) ->
        invalid_items =
          Enum.filter(items, fn item ->
            not (is_map(item) and Map.has_key?(item, :id) and Map.has_key?(item, :type))
          end)

        if length(invalid_items) > 0 do
          add_error(changeset, :items, "contains invalid items: #{inspect(invalid_items)}")
        else
          changeset
        end

      _ ->
        changeset
    end
  end
end
