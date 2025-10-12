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

  @doc """
  Loads things from cache, refreshing stale entries via BGG API.
  """
  @spec load_things_cache([Thing.t()]) :: {:ok, [Thing.t()]} | {:error, atom()}
  def load_things_cache(things) when is_list(things) do
    # Extract Thing IDs from input list
    thing_ids = Enum.map(things, & &1.id)
    
    with {:ok, stale_ids} <- get_stale_thing_ids(thing_ids),
         {:ok, _updated_things} <- update_stale_things(stale_ids),
         {:ok, cached_things} <- get_all_cached_things(thing_ids) do
      {:ok, cached_things}
    end
  end

  @doc """
  Gets Thing IDs that need cache refresh (older than TTL or never cached).
  """
  @spec get_stale_thing_ids([String.t()]) :: {:ok, [String.t()]} | {:error, atom()}
  def get_stale_thing_ids(thing_ids) when is_list(thing_ids) do
    # Calculate the cutoff time for stale cache
    cache_cutoff = DateTime.add(DateTime.utc_now(), -(@cache_ttl_weeks * 7 * 24 * 60 * 60), :second)
    
    try do
      # Query for things that are stale or never cached
      stale_ids =
        from(t in Thing,
          where: t.id in ^thing_ids,
          where: is_nil(t.last_cached) or t.last_cached < ^cache_cutoff,
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
      
      missing_ids = thing_ids |> MapSet.new() |> MapSet.difference(existing_ids) |> MapSet.to_list()
      all_stale_ids = (stale_ids ++ missing_ids) |> Enum.uniq()
      
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
    Logger.info("Updating #{length(thing_ids)} stale things from BGG API")
    
    # Chunk into groups of 20 (BGG API limit)
    chunks = Enum.chunk_every(thing_ids, 20)
    
    try do
      updated_things =
        chunks
        |> Enum.with_index()
        |> Enum.reduce([], fn {chunk, index}, acc ->
          Logger.debug("Processing chunk #{index + 1}/#{length(chunks)} with #{length(chunk)} items")
          
          case update_chunk(chunk) do
            {:ok, chunk_things} ->
              # Rate limiting delay between chunks (except for the last one)
              if index < length(chunks) - 1 do
                :timer.sleep(@rate_limit_delay_ms)
              end
              
              acc ++ chunk_things
            
            {:error, reason} ->
              Logger.warning("Failed to update chunk #{index + 1}: #{inspect(reason)}")
              # Continue with other chunks on failure
              acc
          end
        end)
      
      {:ok, updated_things}
    rescue
      error ->
        Logger.error("Failed to update stale things: #{inspect(error)}")
        {:error, :api_error}
    end
  end

  @doc """
  Retrieves all cached things for the given IDs from database.
  """
  @spec get_all_cached_things([String.t()]) :: {:ok, [Thing.t()]} | {:error, atom()}
  def get_all_cached_things(thing_ids) when is_list(thing_ids) do
    try do
      cached_things =
        from(t in Thing,
          where: t.id in ^thing_ids
        )
        |> Core.Repo.all()
      
      {:ok, cached_things}
    rescue
      error ->
        Logger.error("Failed to get cached things: #{inspect(error)}")
        {:error, :database_error}
    end
  end

  # Private function to update a single chunk of thing IDs
  defp update_chunk(chunk_ids) do
    with {:ok, things} <- BggGateway.things(chunk_ids),
         {:ok, upserted_things} <- upsert_things_batch(things) do
      {:ok, upserted_things}
    end
  end

  # Private function to upsert a batch of things
  defp upsert_things_batch(things) when is_list(things) do
    try do
      upserted_things =
        things
        |> Enum.map(fn thing ->
          case Thing.upsert_thing(thing) do
            {:ok, upserted_thing} -> upserted_thing
            {:error, changeset} ->
              Logger.warning("Failed to upsert thing #{thing.id}: #{inspect(changeset.errors)}")
              nil
          end
        end)
        |> Enum.filter(& &1)  # Remove nil entries
      
      {:ok, upserted_things}
    rescue
      error ->
        Logger.error("Failed to batch upsert things: #{inspect(error)}")
        {:error, :database_error}
    end
  end
end