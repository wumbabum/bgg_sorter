defmodule Core.BggCacher do
  @moduledoc """
  Cache management for BGG Thing data with intelligent freshness detection.
  """

  require Logger
  import Ecto.Query

  alias Core.Schemas.Thing
  alias Core.BggGateway

  @cache_ttl_weeks 1
  @rate_limit_delay_ms 1000
@current_schema_version 3

  @doc """
  Loads things from cache, refreshing stale entries via BGG API.
  Optionally filters and sorts results at the database level.
  """
  @spec load_things_cache([Thing.t()], map(), atom(), atom()) ::
          {:ok, [Thing.t()]} | {:error, atom()}
  def load_things_cache(
        things,
        filters \\ %{},
        sort_field \\ :primary_name,
        sort_direction \\ :asc
      )
      when is_list(things) do
    # Extract Thing IDs from input list
    thing_ids = Enum.map(things, & &1.id)
    Logger.info("🔍 CACHER ENTRY: Loading #{length(thing_ids)} things from cache")
    Logger.info("🔍 CACHER ENTRY: Thing IDs: #{inspect(thing_ids)}")
    Logger.info("🔍 CACHER ENTRY: Filters: #{inspect(filters)}")

    with {:ok, stale_ids} <- get_stale_thing_ids(thing_ids),
         {:ok, _updated_things} <- update_stale_things(stale_ids),
         {:ok, cached_things} <-
           get_all_cached_things(thing_ids, filters, sort_field, sort_direction) do
      Logger.info("🔍 CACHER ENTRY: Successfully loaded #{length(cached_things)} things")
      {:ok, cached_things}
    end
  end

  @doc """
  Gets Thing IDs that need cache refresh (older than TTL or never cached).
  """
  @spec get_stale_thing_ids([String.t()]) :: {:ok, [String.t()]} | {:error, atom()}
  def get_stale_thing_ids(thing_ids) when is_list(thing_ids) do
    # Calculate the cutoff time for stale cache
    cache_cutoff =
      DateTime.add(DateTime.utc_now(), -(@cache_ttl_weeks * 7 * 24 * 60 * 60), :second)

    try do
      # Query for things that are stale, never cached, or have outdated schema version
      stale_ids =
        from(t in Thing,
          where: t.id in ^thing_ids,
          where:
            is_nil(t.last_cached) or
              t.last_cached < ^cache_cutoff or
              is_nil(t.schema_version) or
              t.schema_version < ^@current_schema_version,
          select: t.id
        )
        |> Core.Repo.all()

      # Also include IDs that don't exist in the database at all
      existing_ids =
        from(t in Thing,
          where: t.id in ^thing_ids,
          select: t.id
        )
        |> Core.Repo.all()
        |> MapSet.new()

      missing_ids =
        thing_ids |> MapSet.new() |> MapSet.difference(existing_ids) |> MapSet.to_list()

      all_stale_ids = (stale_ids ++ missing_ids) |> Enum.uniq()

      Logger.info("🔍 CACHER STALE: Found #{length(stale_ids)} stale IDs, #{length(missing_ids)} missing IDs")
      Logger.info("🔍 CACHER STALE: Total stale/missing IDs to update: #{length(all_stale_ids)}")
      Logger.info("🔍 CACHER STALE: IDs: #{inspect(all_stale_ids)}")

      {:ok, all_stale_ids}
    rescue
      error ->
        Logger.error("Failed to get stale thing IDs: #{inspect(error)}")
        {:error, :database_error}
    end
  end

  @doc """
  Updates stale things by calling BGG API with rate limiting and chunking.
  """
  @spec update_stale_things([String.t()]) :: {:ok, [Thing.t()]} | {:error, atom()}
  def update_stale_things([]), do: {:ok, []}

  def update_stale_things(thing_ids) when is_list(thing_ids) do
    start_time = System.monotonic_time(:millisecond)
    Logger.info("🕰️ CACHER TIMING: Starting update of #{length(thing_ids)} stale things")

    # Chunk into groups of 20 (BGG API limit)
    chunks = Enum.chunk_every(thing_ids, 20)

    try do
      updated_things =
        chunks
        |> Enum.with_index()
        |> Enum.reduce([], fn {chunk, index}, acc ->
          chunk_start = System.monotonic_time(:millisecond)
          Logger.info(
            "🕰️ CACHER TIMING: Processing chunk #{index + 1}/#{length(chunks)} with #{length(chunk)} items"
          )

          case update_chunk(chunk) do
            {:ok, chunk_things} ->
              chunk_duration = System.monotonic_time(:millisecond) - chunk_start
              Logger.info("🕰️ CACHER TIMING: Chunk #{index + 1} completed in #{chunk_duration}ms")
              
              # Rate limiting delay between chunks (except for the last one)
              if index < length(chunks) - 1 do
                Logger.info("🕰️ CACHER TIMING: Sleeping #{@rate_limit_delay_ms}ms for rate limiting")
                sleep_start = System.monotonic_time(:millisecond)
                :timer.sleep(@rate_limit_delay_ms)
                sleep_duration = System.monotonic_time(:millisecond) - sleep_start
                Logger.info("🕰️ CACHER TIMING: Sleep completed in #{sleep_duration}ms")
              end

              acc ++ chunk_things

            {:error, reason} ->
              chunk_duration = System.monotonic_time(:millisecond) - chunk_start
              Logger.warning("🕰️ CACHER TIMING: Chunk #{index + 1} failed in #{chunk_duration}ms: #{inspect(reason)}")
              # Continue with other chunks on failure
              acc
          end
        end)

      total_duration = System.monotonic_time(:millisecond) - start_time
      Logger.info("🕰️ CACHER TIMING: Total update completed in #{total_duration}ms (#{Float.round(total_duration/1000, 1)}s)")
      Logger.info("🕰️ CACHER TIMING: Average per chunk: #{Float.round(total_duration/length(chunks), 1)}ms")
      
      {:ok, updated_things}
    rescue
      error ->
        total_duration = System.monotonic_time(:millisecond) - start_time
        Logger.error("🕰️ CACHER TIMING: Failed to update stale things after #{total_duration}ms: #{inspect(error)}")
        {:error, :api_error}
    end
  end

  # Private function to retrieve all cached things for the given IDs from database.
  # Optionally applies database-level filtering and sorting for performance.
  @spec get_all_cached_things([String.t()], map(), atom(), atom()) ::
          {:ok, [Thing.t()]} | {:error, atom()}
  defp get_all_cached_things(
         thing_ids,
         filters \\ %{},
         sort_field \\ :primary_name,
         sort_direction \\ :asc
       )
       when is_list(thing_ids) do
    try do
      cached_things =
        from(t in Thing,
          where: t.id in ^thing_ids,
          # Preload mechanics to prevent N+1 queries
          preload: [:mechanics]
        )
        |> with_filters(filters)
        |> with_sorting(sort_field, sort_direction)
        |> Core.Repo.all()
      
      # Debug mechanics loading
      Enum.each(cached_things, fn thing ->
        Logger.info("🔍 CACHER DEBUG: Thing #{thing.id} (#{thing.primary_name}) has #{length(thing.mechanics || [])} mechanics")
        if thing.mechanics && length(thing.mechanics) > 0 do
          Logger.info("🔍 CACHER DEBUG: First mechanic: #{Enum.at(thing.mechanics, 0).name}")
        end
      end)

      {:ok, cached_things}
    rescue
      error ->
        Logger.error("Failed to get cached things: #{inspect(error)}")
        {:error, :database_error}
    end
  end

  # Private function to update a single chunk of thing IDs
  defp update_chunk(chunk_ids) do
    Logger.info("🔍 CACHER CHUNK: Updating chunk with IDs: #{inspect(chunk_ids)}")
    
    with {:ok, things} <- BggGateway.things(chunk_ids) do
      Logger.info("🔍 CACHER CHUNK: BGG API returned #{length(things)} things")
      
      # Log mechanics data for each thing
      Enum.each(things, fn thing ->
        raw_mechanics = Map.get(thing, :raw_mechanics, [])
        Logger.info("🔍 CACHER CHUNK: Thing #{thing.id} (#{thing.primary_name}) has #{length(raw_mechanics)} raw mechanics")
        if length(raw_mechanics) > 0 do
          Logger.info("🔍 CACHER CHUNK: Thing #{thing.id} mechanics: #{inspect(Enum.take(raw_mechanics, 3))}#{if length(raw_mechanics) > 3, do: "...", else: ""}")
        end
      end)
      
      case upsert_things_batch(things) do
        {:ok, upserted_things} -> {:ok, upserted_things}
        error -> 
          Logger.error("🔍 CACHER CHUNK: Failed to upsert batch: #{inspect(error)}")
          error
      end
    else
      error ->
        Logger.error("🔍 CACHER CHUNK: BGG API call failed: #{inspect(error)}")
        error
    end
  end

  # Private function to apply database-level filters to a query
  # Accepts same filter format as Thing.filter_by/2 for consistency
  defp with_filters(query, filters) when map_size(filters) == 0, do: query

  defp with_filters(query, filters) do
    # Apply weight defaults before filtering (same logic as Thing schema)
    processed_filters = apply_weight_defaults(filters)
    Enum.reduce(processed_filters, query, &apply_filter/2)
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

  # Apply individual filter conditions to the query
  defp apply_filter({:primary_name, value}, query) when value not in [nil, ""] do
    search_term = "%#{String.downcase(value)}%"
    from(t in query, where: ilike(t.primary_name, ^search_term))
  end

  defp apply_filter({:players, value}, query) when value not in [nil, ""] do
    case parse_integer(value) do
      player_count when is_integer(player_count) ->
        from(t in query,
          where:
            fragment("CAST(? AS INTEGER) >= CAST(? AS INTEGER)", ^player_count, t.minplayers) and
              fragment("CAST(? AS INTEGER) <= CAST(? AS INTEGER)", ^player_count, t.maxplayers)
        )

      _ ->
        query
    end
  end

  defp apply_filter({:playingtime, value}, query) when value not in [nil, ""] do
    case parse_integer(value) do
      target_time when is_integer(target_time) ->
        from(t in query,
          where:
            fragment("CAST(? AS INTEGER) >= CAST(? AS INTEGER)", ^target_time, t.minplaytime) and
              fragment("CAST(? AS INTEGER) <= CAST(? AS INTEGER)", ^target_time, t.maxplaytime)
        )

      _ ->
        query
    end
  end

  defp apply_filter({:rank, value}, query) when value not in [nil, ""] do
    case parse_integer(value) do
      max_rank when is_integer(max_rank) ->
        from(t in query,
          where:
            fragment(
              "CAST(? AS INTEGER) > 0 AND CAST(? AS INTEGER) <= ?",
              t.rank,
              t.rank,
              ^max_rank
            )
        )

      _ ->
        query
    end
  end

  defp apply_filter({:average, value}, query) when value not in [nil, ""] do
    case parse_float(value) do
      min_rating when is_float(min_rating) ->
        from(t in query, where: fragment("CAST(? AS FLOAT) >= ?", t.average, ^min_rating))

      _ ->
        query
    end
  end

  defp apply_filter({:averageweight_min, value}, query) when value not in [nil, ""] do
    case parse_float(value) do
      min_weight when is_float(min_weight) ->
        from(t in query, where: fragment("CAST(? AS FLOAT) >= ?", t.averageweight, ^min_weight))

      _ ->
        query
    end
  end

  defp apply_filter({:averageweight_max, value}, query) when value not in [nil, ""] do
    case parse_float(value) do
      max_weight when is_float(max_weight) ->
        from(t in query, where: fragment("CAST(? AS FLOAT) <= ?", t.averageweight, ^max_weight))

      _ ->
        query
    end
  end

  defp apply_filter({:description, value}, query) when value not in [nil, ""] do
    search_term = "%#{String.downcase(value)}%"
    from(t in query, where: ilike(t.description, ^search_term))
  end

  defp apply_filter({:selected_mechanics, selected_mechanics}, query)
       when is_list(selected_mechanics) and selected_mechanics != [] do
    # Filter out empty strings and normalize mechanic IDs
    clean_mechanic_ids =
      selected_mechanics
      |> Enum.filter(fn id -> is_binary(id) and String.trim(id) != "" end)
      |> Enum.map(&String.trim/1)

    case clean_mechanic_ids do
      [] ->
        query

      mechanic_ids ->
        # Use JOIN with GROUP BY to find things that have ALL selected mechanics by ID
        from [t] in query,
          join: tm in assoc(t, :thing_mechanics),
          join: m in assoc(tm, :mechanic),
          where: m.id in ^mechanic_ids,
          group_by: t.id,
          having: count(m.id) == ^length(mechanic_ids)
    end
  end

  # Skip unknown filters
  defp apply_filter(_, query), do: query

  # Helper functions for parsing (duplicated from Thing schema for now)
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

  # Private function to apply database-level sorting to a query
  defp with_sorting(query, sort_field, sort_direction) do
    case sort_field do
      :primary_name ->
        apply_sort_direction(query, :primary_name, sort_direction, &sort_by_name/2)

      :players ->
        apply_sort_direction(query, :minplayers, sort_direction, &sort_by_players/2)

      :average ->
        apply_sort_direction(query, :average, sort_direction, &sort_by_rating/2)

      :averageweight ->
        apply_sort_direction(query, :averageweight, sort_direction, &sort_by_weight/2)

      _ ->
        # Default to primary_name sorting for unknown fields
        apply_sort_direction(query, :primary_name, :asc, &sort_by_name/2)
    end
  end

  defp apply_sort_direction(query, _field, direction, sort_function) do
    sort_function.(query, direction)
  end

  # Sort by game name (case-insensitive)
  defp sort_by_name(query, :asc) do
    from(t in query, order_by: [asc: fragment("LOWER(?)", t.primary_name)])
  end

  defp sort_by_name(query, :desc) do
    from(t in query, order_by: [desc: fragment("LOWER(?)", t.primary_name)])
  end

  # Sort by player count (minimum players, with proper integer casting and NULL handling)
  defp sort_by_players(query, :asc) do
    from(t in query,
      order_by: [asc: fragment("CAST(? AS INTEGER)", t.minplayers), asc_nulls_last: t.minplayers]
    )
  end

  defp sort_by_players(query, :desc) do
    from(t in query,
      order_by: [
        desc: fragment("CAST(? AS INTEGER)", t.minplayers),
        desc_nulls_last: t.minplayers
      ]
    )
  end

  # Sort by BGG rating (with proper float casting and NULL handling)
  defp sort_by_rating(query, :asc) do
    from(t in query,
      order_by: [asc: fragment("CAST(? AS FLOAT)", t.average), asc_nulls_last: t.average]
    )
  end

  defp sort_by_rating(query, :desc) do
    from(t in query,
      order_by: [desc: fragment("CAST(? AS FLOAT)", t.average), desc_nulls_last: t.average]
    )
  end

  # Sort by complexity weight (with proper float casting and NULL handling)
  defp sort_by_weight(query, :asc) do
    from(t in query,
      order_by: [
        asc: fragment("CAST(? AS FLOAT)", t.averageweight),
        asc_nulls_last: t.averageweight
      ]
    )
  end

  defp sort_by_weight(query, :desc) do
    from(t in query,
      order_by: [
        desc: fragment("CAST(? AS FLOAT)", t.averageweight),
        desc_nulls_last: t.averageweight
      ]
    )
  end

  # Private function to upsert a batch of things
  defp upsert_things_batch(things) when is_list(things) do
    Logger.info("🔍 CACHER BATCH: Starting upsert for #{length(things)} things")
    
    try do
      upserted_things =
        things
        |> Enum.with_index()
        |> Enum.map(fn {thing, index} ->
          Logger.info("🔍 CACHER BATCH: Processing thing #{index + 1}/#{length(things)}: #{thing.id} (#{Map.get(thing, :primary_name, "Unknown")})}")
          
          case Thing.upsert_thing(thing) do
            {:ok, upserted_thing} ->
              Logger.info("🔍 CACHER BATCH: Successfully upserted thing #{thing.id}")
              upserted_thing

            {:error, changeset} ->
              Logger.warning("🔍 CACHER BATCH: Failed to upsert thing #{thing.id}: #{inspect(changeset.errors)}")
              nil
          end
        end)
        # Remove nil entries
        |> Enum.filter(& &1)

      Logger.info("🔍 CACHER BATCH: Completed batch upsert - #{length(upserted_things)}/#{length(things)} successful")
      {:ok, upserted_things}
    rescue
      error ->
        Logger.error("🔍 CACHER BATCH: Failed to batch upsert things: #{inspect(error)}")
        {:error, :database_error}
    end
  end
end
