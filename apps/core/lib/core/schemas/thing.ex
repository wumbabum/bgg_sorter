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
          mechanics_checksum: String.t() | nil,
          schema_version: integer() | nil,
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
    field :mechanics_checksum, :string
    field :schema_version, :integer, default: 2

    # Associations
    has_many :thing_mechanics, Core.Schemas.ThingMechanic, on_delete: :delete_all

    many_to_many :mechanics, Core.Schemas.Mechanic,
      join_through: Core.Schemas.ThingMechanic,
      on_replace: :delete

    field :last_cached, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(id type schema_version)a
  @optional_fields ~w(subtype thumbnail image primary_name description yearpublished minplayers maxplayers playingtime minplaytime maxplaytime minage usersrated average bayesaverage rank owned averageweight mechanics_checksum last_cached)a

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
    # Extract raw_mechanics if present (from BggGateway)
    raw_mechanics = Map.get(params, "raw_mechanics") || Map.get(params, :raw_mechanics)

    # Process mechanics and generate checksum
    {mechanics_list, new_checksum} = process_raw_mechanics(raw_mechanics)

    # Ensure last_cached and schema_version are set with current values
    current_time = DateTime.utc_now()
    params_with_timestamp =
      params
      |> stringify_keys()
      |> Map.delete("raw_mechanics")  # Remove virtual field
      |> Map.put("last_cached", current_time)
      |> Map.put("schema_version", 2)
      # Don't set mechanics_checksum yet - we'll do that after processing mechanics

    changeset = changeset(%__MODULE__{}, params_with_timestamp)

    case changeset.valid? do
      true ->
        with {:ok, upserted_thing} <- upsert_thing_record(changeset),
             {:ok, updated_thing} <- update_thing_mechanics(upserted_thing, mechanics_list, new_checksum) do
          {:ok, updated_thing}
        end
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
    # Apply weight defaults and then process filters
    processed_filters = apply_weight_defaults(filters)

    # Only process filters that are not nil or empty strings
    active_filters =
      processed_filters
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Enum.into(%{})

    if Enum.empty?(active_filters) do
      things
    else
      Enum.filter(things, &matches_all_filters?(&1, active_filters))
    end
  end

  # Apply weight filter defaults: min=0 if only max provided, max=5 if only min provided
  defp apply_weight_defaults(filters) do
    min_weight = Map.get(filters, :averageweight_min)
    max_weight = Map.get(filters, :averageweight_max)

    cond do
      # Only min provided, default max to 5
      min_weight not in [nil, ""] and max_weight in [nil, ""] ->
        Map.put(filters, :averageweight_max, "5")

      # Only max provided, default min to 0
      min_weight in [nil, ""] and max_weight not in [nil, ""] ->
        Map.put(filters, :averageweight_min, "0")

      # Both provided or neither provided, no changes
      true ->
        filters
    end
  end

  # Check if a thing matches all active filters
  defp matches_all_filters?(thing, filters) do
    Enum.all?(filters, fn {key, value} ->
      matches_filter?(thing, key, value)
    end)
  end

  # Individual filter matching functions - one line each using helper functions
  defp matches_filter?(thing, :primary_name, search_term),
    do: string_contains?(thing.primary_name, search_term)

  defp matches_filter?(thing, :players, target_players),
    do: in_integer_range?(target_players, thing.minplayers, thing.maxplayers)

  defp matches_filter?(thing, :playingtime, target_time),
    do: in_integer_range?(target_time, thing.minplaytime, thing.maxplaytime)

  defp matches_filter?(thing, :rank, max_rank), do: integer_lte_positive?(thing.rank, max_rank)
  defp matches_filter?(thing, :average, min_rating), do: float_gte?(thing.average, min_rating)

  defp matches_filter?(thing, :averageweight_min, min_weight),
    do: float_gte?(thing.averageweight, min_weight)

  defp matches_filter?(thing, :averageweight_max, max_weight),
    do: float_lte?(thing.averageweight, max_weight)

  defp matches_filter?(thing, :description, search_term),
    do: string_contains?(thing.description, search_term)

  defp matches_filter?(thing, :selected_mechanics, selected_mechanics),
    do: has_all_mechanics?(thing.mechanics, selected_mechanics)

  # Skip unknown filters
  defp matches_filter?(_thing, _key, _value), do: true

  # Helper functions for filter matching
  defp string_contains?(field_value, search_term) do
    String.contains?(String.downcase(field_value || ""), String.downcase(search_term))
  end

  defp integer_lte_positive?(field_value, max_value) do
    case {parse_integer(field_value), parse_integer(max_value)} do
      {field_int, max_int} when is_integer(field_int) and is_integer(max_int) and field_int > 0 ->
        field_int <= max_int

      _ ->
        true
    end
  end

  defp in_integer_range?(target_value, min_field, max_field) do
    case {parse_integer(target_value), parse_integer(min_field), parse_integer(max_field)} do
      {target, min_val, max_val}
      when is_integer(target) and is_integer(min_val) and is_integer(max_val) ->
        target >= min_val and target <= max_val

      _ ->
        true
    end
  end

  defp float_gte?(field_value, min_value) do
    case {parse_float(field_value), parse_float(min_value)} do
      {field_float, min_float} when is_float(field_float) and is_float(min_float) ->
        field_float >= min_float

      _ ->
        true
    end
  end

  defp float_lte?(field_value, max_value) do
    case {parse_float(field_value), parse_float(max_value)} do
      {field_float, max_float} when is_float(field_float) and is_float(max_float) ->
        field_float <= max_float

      _ ->
        true
    end
  end

  defp has_all_mechanics?(thing_mechanics, selected_mechanics) when is_list(selected_mechanics) do
    # Filter out empty strings and normalize
    clean_selected =
      selected_mechanics
      |> Enum.filter(fn id -> is_binary(id) and String.trim(id) != "" end)
      |> Enum.map(&String.trim/1)

    case clean_selected do
      # No mechanics filter applied
      [] ->
        true

      mechanic_ids ->
        # Extract mechanic IDs from preloaded mechanics association
        thing_mechanic_ids =
          case thing_mechanics do
            # Association not preloaded
            %Ecto.Association.NotLoaded{} -> []
            mechanics_list when is_list(mechanics_list) -> Enum.map(mechanics_list, & &1.id)
            # No mechanics
            nil -> []
          end

        # Check if thing has ALL selected mechanics (by ID)
        Enum.all?(mechanic_ids, fn mechanic_id -> mechanic_id in thing_mechanic_ids end)
    end
  end

  defp has_all_mechanics?(_thing_mechanics, _selected_mechanics), do: true

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

  @doc "Generates a checksum for a list of mechanic names"
  def generate_mechanics_checksum([]), do: nil
  def generate_mechanics_checksum(nil), do: nil

  def generate_mechanics_checksum(mechanics_list) when is_list(mechanics_list) do
    mechanics_list
    # Consistent ordering
    |> Enum.sort()
    |> Enum.join("|")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  # Private helper functions for mechanics processing

  defp process_raw_mechanics(nil), do: {[], nil}
  defp process_raw_mechanics([]), do: {[], nil}

  defp process_raw_mechanics(mechanics_list) when is_list(mechanics_list) do
    # Filter out empty strings and normalize
    clean_mechanics =
      mechanics_list
      |> Enum.filter(fn name -> is_binary(name) and String.trim(name) != "" end)
      |> Enum.map(&String.trim/1)

    case clean_mechanics do
      [] -> {[], nil}
      mechanics -> {mechanics, generate_mechanics_checksum(mechanics)}
    end
  end

  defp upsert_thing_record(changeset) do
    Core.Repo.insert(changeset,
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: :id
    )
  end

  defp update_thing_mechanics(thing, [], nil) do
    # No mechanics to process
    {:ok, thing}
  end

  defp update_thing_mechanics(thing, mechanics_list, new_checksum) do
    # Check if mechanics need updating by comparing checksums
    current_checksum = thing.mechanics_checksum
    
    if current_checksum == new_checksum do
      # Checksums match, no update needed
      {:ok, thing}
    else
      # Update mechanics associations
      with {:ok, mechanic_ids} <- upsert_mechanics_bulk(mechanics_list),
           {:ok, updated_thing} <- update_thing_associations(thing, mechanic_ids, new_checksum) do
        {:ok, updated_thing}
      end
    end
  end

  defp upsert_mechanics_bulk(mechanics_list) do
    import Ecto.Query
    alias Core.Schemas.Mechanic
    
    # Prepare bulk insert data with generated UUIDs and slugs
    current_time = DateTime.utc_now() |> DateTime.truncate(:second)
    mechanics_params =
      mechanics_list
      |> Enum.map(fn name ->
        %{
          id: Ecto.UUID.generate(),
          name: name,
          slug: Mechanic.generate_slug(name),
          inserted_at: current_time,
          updated_at: current_time
        }
      end)
    
    # Bulk upsert mechanics using insert_all with conflict resolution
    {_count, _mechanics} =
      Core.Repo.insert_all(
        Mechanic,
        mechanics_params,
        on_conflict: :nothing,
        conflict_target: :name,
        # We'll query them separately for reliability
        returning: false
      )
    
    # Get all mechanic IDs (including existing ones not returned by insert_all)
    mechanic_ids =
      from(m in Mechanic, where: m.name in ^mechanics_list, select: m.id)
      |> Core.Repo.all()
    
    {:ok, mechanic_ids}
  end

  defp update_thing_associations(thing, mechanic_ids, new_checksum) do
    alias Core.Schemas.ThingMechanic

    # Build new ThingMechanic records
    current_time = DateTime.utc_now() |> DateTime.truncate(:second)
    thing_mechanic_records =
      Enum.map(mechanic_ids, fn mechanic_id ->
        %{
          id: Ecto.UUID.generate(),
          thing_id: thing.id,
          mechanic_id: mechanic_id,
          inserted_at: current_time
        }
      end)

    # Use Multi for atomic transaction
    result =
      Ecto.Multi.new()
      |> Ecto.Multi.delete_all(:delete_existing, ThingMechanic.for_thing(thing.id))
      |> Ecto.Multi.insert_all(:insert_new, ThingMechanic, thing_mechanic_records)
      |> Ecto.Multi.update(
        :update_checksum,
        changeset(thing, %{mechanics_checksum: new_checksum})
      )
      |> Core.Repo.transaction()

    case result do
      {:ok, %{update_checksum: updated_thing}} ->
        {:ok, updated_thing}

      {:error, _step, error, _changes} ->
        {:error, error}
    end
  end
end
