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

  # Individual filter matching functions
  defp matches_filter?(thing, :primary_name, search_term) do
    String.contains?(String.downcase(thing.primary_name || ""), String.downcase(search_term))
  end

  defp matches_filter?(thing, :yearpublished_min, min_year) do
    case {parse_integer(thing.yearpublished), parse_integer(min_year)} do
      {thing_year, min_year_int} when is_integer(thing_year) and is_integer(min_year_int) ->
        thing_year >= min_year_int
      _ ->
        true
    end
  end

  defp matches_filter?(thing, :yearpublished_max, max_year) do
    case {parse_integer(thing.yearpublished), parse_integer(max_year)} do
      {thing_year, max_year_int} when is_integer(thing_year) and is_integer(max_year_int) ->
        thing_year <= max_year_int
      _ ->
        true
    end
  end

  defp matches_filter?(thing, :players, target_players) do
    case {parse_integer(thing.minplayers), parse_integer(thing.maxplayers), parse_integer(target_players)} do
      {min_p, max_p, target} when is_integer(min_p) and is_integer(max_p) and is_integer(target) ->
        target >= min_p and target <= max_p
      _ ->
        true
    end
  end

  defp matches_filter?(thing, :playingtime_min, min_time) do
    case {parse_integer(thing.playingtime), parse_integer(min_time)} do
      {thing_time, min_time_int} when is_integer(thing_time) and is_integer(min_time_int) ->
        thing_time >= min_time_int
      _ ->
        true
    end
  end

  defp matches_filter?(thing, :playingtime_max, max_time) do
    case {parse_integer(thing.playingtime), parse_integer(max_time)} do
      {thing_time, max_time_int} when is_integer(thing_time) and is_integer(max_time_int) ->
        thing_time <= max_time_int
      _ ->
        true
    end
  end

  defp matches_filter?(thing, :minage, max_minage) do
    case {parse_integer(thing.minage), parse_integer(max_minage)} do
      {thing_minage, max_minage_int} when is_integer(thing_minage) and is_integer(max_minage_int) ->
        # Game min age should be <= filter (younger or same)
        thing_minage <= max_minage_int
      _ ->
        true
    end
  end

  defp matches_filter?(thing, :rank, max_rank) do
    case {parse_integer(thing.rank), parse_integer(max_rank)} do
      {thing_rank, max_rank_int} when is_integer(thing_rank) and is_integer(max_rank_int) and thing_rank > 0 ->
        # Lower rank number is better
        thing_rank <= max_rank_int
      _ ->
        true
    end
  end

  defp matches_filter?(thing, :average, min_rating) do
    case {parse_float(thing.average), parse_float(min_rating)} do
      {thing_rating, min_rating_float} when is_float(thing_rating) and is_float(min_rating_float) ->
        thing_rating >= min_rating_float
      _ ->
        true
    end
  end

  defp matches_filter?(thing, :averageweight_min, min_weight) do
    case {parse_float(thing.averageweight), parse_float(min_weight)} do
      {thing_weight, min_weight_float} when is_float(thing_weight) and is_float(min_weight_float) ->
        thing_weight >= min_weight_float
      _ ->
        true
    end
  end

  defp matches_filter?(thing, :averageweight_max, max_weight) do
    case {parse_float(thing.averageweight), parse_float(max_weight)} do
      {thing_weight, max_weight_float} when is_float(thing_weight) and is_float(max_weight_float) ->
        thing_weight <= max_weight_float
      _ ->
        true
    end
  end

  defp matches_filter?(thing, :description, search_term) do
    String.contains?(String.downcase(thing.description || ""), String.downcase(search_term))
  end

  # Skip unknown filters
  defp matches_filter?(_thing, _key, _value), do: true

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
