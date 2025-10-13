defmodule Core.Schemas.Thing do
  @moduledoc """
  Schema representing detailed BoardGameGeek thing information.
  """

  use Ecto.Schema
  import Ecto.Changeset

  require Logger

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
          averageweight: String.t() | nil,
          last_cached: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :string, [autogenerate: false]}
  schema "things" do
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
    field :last_cached, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(id type)a
  @optional_fields ~w(subtype thumbnail image primary_name description yearpublished minplayers maxplayers playingtime minplaytime maxplaytime minage usersrated average bayesaverage rank owned averageweight last_cached)a

  @doc "Generates a changeset for the Thing schema."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(thing \\ %__MODULE__{}, params) do
    thing
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  @doc "Upserts a thing record in the database."
  @spec upsert_thing(map() | t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def upsert_thing(%__MODULE__{} = thing) do
    # Convert struct to map, filtering out Ecto metadata
    params =
      thing
      |> Map.from_struct()
      |> Enum.reject(fn {key, _val} -> key in [:__meta__, :inserted_at, :updated_at] end)
      |> Enum.into(%{})
      |> stringify_keys()

    upsert_thing(params)
  end

  def upsert_thing(params) when is_map(params) do
    # Ensure last_cached is set with current timestamp
    current_time = DateTime.utc_now()
    params_with_timestamp =
      params
      |> stringify_keys()
      |> Map.put("last_cached", current_time)

    changeset = changeset(%__MODULE__{}, params_with_timestamp)

    case changeset.valid? do
      true ->
        Core.Repo.insert(changeset,
          on_conflict: {:replace_all_except, [:id, :inserted_at]},
          conflict_target: :id
        )
      false ->
        {:error, changeset}
    end
  end

  # Helper function to convert atom keys to string keys
  defp stringify_keys(map) when is_map(map) do
    for {key, val} <- map, into: %{} do
      {to_string(key), val}
    end
  end

  @doc "Filters a list of things based on the provided filter criteria."
  @spec filter_by([t()], map()) :: [t()]
  def filter_by(things, filters \\ %{}) do
    Logger.info("Filtering #{length(things)} things with filters: #{inspect(filters)}")
    # Only process filters that are not nil or empty strings
    active_filters =
      filters
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Enum.into(%{})

    if Enum.empty?(active_filters) do
      things
    else
      Enum.filter(things, &matches_all_filters?(&1, active_filters))
    end
  end

  # Check if a thing matches all active filters
  defp matches_all_filters?(thing, filters) do
    Enum.all?(filters, fn {key, value} ->
      matches_filter?(thing, key, value)
    end)
  end

  # Individual filter matching functions - one line each using helper functions
  defp matches_filter?(thing, :primary_name, search_term), do: string_contains?(thing.primary_name, search_term)
  defp matches_filter?(thing, :yearpublished_min, min_year), do: integer_gte?(thing.yearpublished, min_year)
  defp matches_filter?(thing, :yearpublished_max, max_year), do: integer_lte?(thing.yearpublished, max_year)
  defp matches_filter?(thing, :players, target_players), do: in_integer_range?(target_players, thing.minplayers, thing.maxplayers)
  defp matches_filter?(thing, :playingtime, target_time), do: in_integer_range?(target_time, thing.minplaytime, thing.maxplaytime)
  defp matches_filter?(thing, :minage, max_minage), do: integer_lte?(thing.minage, max_minage)
  defp matches_filter?(thing, :rank, max_rank), do: integer_lte_positive?(thing.rank, max_rank)
  defp matches_filter?(thing, :average, min_rating), do: float_gte?(thing.average, min_rating)
  defp matches_filter?(thing, :averageweight_min, min_weight), do: float_gte?(thing.averageweight, min_weight)
  defp matches_filter?(thing, :averageweight_max, max_weight), do: float_lte?(thing.averageweight, max_weight)
  defp matches_filter?(thing, :description, search_term), do: string_contains?(thing.description, search_term)

  # Skip unknown filters
  defp matches_filter?(_thing, _key, _value), do: true

  # Helper functions for filter matching
  defp string_contains?(field_value, search_term) do
    String.contains?(String.downcase(field_value || ""), String.downcase(search_term))
  end

  defp integer_gte?(field_value, min_value) do
    case {parse_integer(field_value), parse_integer(min_value)} do
      {field_int, min_int} when is_integer(field_int) and is_integer(min_int) -> field_int >= min_int
      _ -> true
    end
  end

  defp integer_lte?(field_value, max_value) do
    case {parse_integer(field_value), parse_integer(max_value)} do
      {field_int, max_int} when is_integer(field_int) and is_integer(max_int) -> field_int <= max_int
      _ -> true
    end
  end

  defp integer_lte_positive?(field_value, max_value) do
    case {parse_integer(field_value), parse_integer(max_value)} do
      {field_int, max_int} when is_integer(field_int) and is_integer(max_int) and field_int > 0 -> field_int <= max_int
      _ -> true
    end
  end

  defp in_integer_range?(target_value, min_field, max_field) do
    case {parse_integer(target_value), parse_integer(min_field), parse_integer(max_field)} do
      {target, min_val, max_val} when is_integer(target) and is_integer(min_val) and is_integer(max_val) ->
        target >= min_val and target <= max_val
      _ -> true
    end
  end

  defp float_gte?(field_value, min_value) do
    case {parse_float(field_value), parse_float(min_value)} do
      {field_float, min_float} when is_float(field_float) and is_float(min_float) -> field_float >= min_float
      _ -> true
    end
  end

  defp float_lte?(field_value, max_value) do
    case {parse_float(field_value), parse_float(max_value)} do
      {field_float, max_float} when is_float(field_float) and is_float(max_float) -> field_float <= max_float
      _ -> true
    end
  end

  # Helper functions for parsing
  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int_val, _} -> int_val
      _ -> nil
    end
  end

  defp parse_integer(value) when is_integer(value), do: value
  defp parse_integer(_), do: nil

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float_val, _} -> float_val
      _ -> nil
    end
  end

  defp parse_float(value) when is_float(value), do: value
  defp parse_float(value) when is_integer(value), do: value * 1.0
  defp parse_float(_), do: nil
end
