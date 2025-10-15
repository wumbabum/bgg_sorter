defmodule Core.CacheMonitor do
  @moduledoc """
  Monitoring utilities for BGG data caching system performance tracking.
  """

  require Logger
  import Ecto.Query

  alias Core.Schemas.Thing

  @doc """
  Gets cache statistics including hit rate, freshness distribution, and storage metrics.
  """
  @spec cache_stats() :: %{
          total_cached_items: integer(),
          fresh_items: integer(),
          stale_items: integer(),
          cache_hit_rate: float(),
          average_cache_age_days: float(),
          storage_size_mb: float()
        }
  def cache_stats do
    total_items = get_total_cached_items()
    fresh_items = get_fresh_items_count()
    stale_items = get_stale_items_count()

    cache_hit_rate = if total_items > 0, do: fresh_items / total_items * 100, else: 0.0
    avg_age_days = get_average_cache_age_days()
    storage_size = estimate_storage_size_mb()

    %{
      total_cached_items: total_items,
      fresh_items: fresh_items,
      stale_items: stale_items,
      cache_hit_rate: Float.round(cache_hit_rate, 2),
      average_cache_age_days: Float.round(avg_age_days, 2),
      storage_size_mb: Float.round(storage_size, 2)
    }
  end

  @doc """
  Logs current cache performance metrics at info level.
  """
  @spec log_cache_performance() :: :ok
  def log_cache_performance do
    stats = cache_stats()

    Logger.info("""
    BGG Cache Performance Metrics:
    - Total Cached Items: #{stats.total_cached_items}
    - Fresh Items: #{stats.fresh_items}
    - Stale Items: #{stats.stale_items}
    - Cache Hit Rate: #{stats.cache_hit_rate}%
    - Average Cache Age: #{stats.average_cache_age_days} days
    - Storage Size: #{stats.storage_size_mb} MB
    """)
  end

  @doc """
  Gets cache performance metrics for a specific time period.
  """
  @spec period_stats(DateTime.t(), DateTime.t()) :: %{
          items_cached_in_period: integer(),
          items_updated_in_period: integer(),
          api_calls_saved: integer()
        }
  def period_stats(start_time, end_time) do
    items_cached = get_items_cached_in_period(start_time, end_time)
    items_updated = get_items_updated_in_period(start_time, end_time)

    # Estimate API calls saved (items that were fresh and didn't need API calls)
    api_calls_saved = get_fresh_items_accessed_in_period(start_time, end_time)

    %{
      items_cached_in_period: items_cached,
      items_updated_in_period: items_updated,
      api_calls_saved: api_calls_saved
    }
  end

  @doc """
  Gets the oldest cached items that might benefit from refresh.
  """
  @spec oldest_cached_items(integer()) :: [Thing.t()]
  def oldest_cached_items(limit \\ 10) do
    from(t in Thing,
      where: not is_nil(t.last_cached),
      order_by: [asc: t.last_cached],
      limit: ^limit
    )
    |> Core.Repo.all()
  end

  @doc """
  Gets cache freshness distribution by age ranges.
  """
  @spec freshness_distribution() :: %{
          # < 1 day
          very_fresh: integer(),
          # 1-3 days  
          fresh: integer(),
          # 3-7 days
          aging: integer(),
          # > 7 days
          stale: integer(),
          # nil last_cached
          never_cached: integer()
        }
  def freshness_distribution do
    now = DateTime.utc_now()
    one_day_ago = DateTime.add(now, -1 * 24 * 60 * 60, :second)
    three_days_ago = DateTime.add(now, -3 * 24 * 60 * 60, :second)
    seven_days_ago = DateTime.add(now, -7 * 24 * 60 * 60, :second)

    %{
      very_fresh: get_items_cached_after(one_day_ago),
      fresh: get_items_cached_between(three_days_ago, one_day_ago),
      aging: get_items_cached_between(seven_days_ago, three_days_ago),
      stale: get_items_cached_before(seven_days_ago),
      never_cached: get_never_cached_count()
    }
  end

  # Private helper functions

  defp get_total_cached_items do
    from(t in Thing, select: count())
    |> Core.Repo.one()
  end

  defp get_fresh_items_count do
    cache_cutoff = DateTime.add(DateTime.utc_now(), -7 * 24 * 60 * 60, :second)

    from(t in Thing,
      where: not is_nil(t.last_cached) and t.last_cached > ^cache_cutoff,
      select: count()
    )
    |> Core.Repo.one()
  end

  defp get_stale_items_count do
    cache_cutoff = DateTime.add(DateTime.utc_now(), -7 * 24 * 60 * 60, :second)

    from(t in Thing,
      where: is_nil(t.last_cached) or t.last_cached <= ^cache_cutoff,
      select: count()
    )
    |> Core.Repo.one()
  end

  defp get_average_cache_age_days do
    now = DateTime.utc_now()

    result =
      from(t in Thing,
        where: not is_nil(t.last_cached),
        select: avg(fragment("EXTRACT(EPOCH FROM ? - ?)", ^now, t.last_cached))
      )
      |> Core.Repo.one()

    case result do
      nil -> 0.0
      # Convert to days
      age_seconds -> age_seconds / (24 * 60 * 60)
    end
  end

  defp estimate_storage_size_mb do
    # Rough estimate based on typical Thing size
    total_items = get_total_cached_items()
    # bytes, rough estimate
    estimated_size_per_item = 2048
    total_bytes = total_items * estimated_size_per_item
    # Convert to MB
    total_bytes / (1024 * 1024)
  end

  defp get_items_cached_in_period(start_time, end_time) do
    from(t in Thing,
      where: t.inserted_at >= ^start_time and t.inserted_at <= ^end_time,
      select: count()
    )
    |> Core.Repo.one()
  end

  defp get_items_updated_in_period(start_time, end_time) do
    from(t in Thing,
      where: not is_nil(t.last_cached),
      where: t.last_cached >= ^start_time and t.last_cached <= ^end_time,
      select: count()
    )
    |> Core.Repo.one()
  end

  defp get_fresh_items_accessed_in_period(_start_time, _end_time) do
    # This would require access logging to implement properly
    # For now, estimate based on fresh items count
    get_fresh_items_count()
  end

  defp get_items_cached_after(timestamp) do
    from(t in Thing,
      where: not is_nil(t.last_cached) and t.last_cached > ^timestamp,
      select: count()
    )
    |> Core.Repo.one()
  end

  defp get_items_cached_between(start_time, end_time) do
    from(t in Thing,
      where: not is_nil(t.last_cached),
      where: t.last_cached > ^start_time and t.last_cached <= ^end_time,
      select: count()
    )
    |> Core.Repo.one()
  end

  defp get_items_cached_before(timestamp) do
    from(t in Thing,
      where: not is_nil(t.last_cached) and t.last_cached <= ^timestamp,
      select: count()
    )
    |> Core.Repo.one()
  end

  defp get_never_cached_count do
    from(t in Thing,
      where: is_nil(t.last_cached),
      select: count()
    )
    |> Core.Repo.one()
  end
end
