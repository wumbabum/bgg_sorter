defmodule Dispatch.Workers.PrecacheWorker do
  @moduledoc """
  Daily cron worker that precaches top-ranked BGG games.
  Fetches the top 300 uncached games by BGG rank in chunks of 20
  with a 10-second delay between chunks.
  """

  use Oban.Worker, queue: :precache, max_attempts: 1

  require Logger

  alias Core.BggGateway
  alias Core.Schemas.Thing

  @chunk_size 20
  @rate_limit_delay_ms 10_000
  @default_limit 300

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    limit = Map.get(job.args, "limit", @default_limit)

    Logger.info("PrecacheWorker starting: fetching top #{limit} uncached games")

    {uncached_ids, end_of_list?} =
      case Dispatch.BggRanks.uncached_top_n(limit) do
        {:ok, ids} -> {ids, false}
        {:error, :end_of_list} -> {[], true}
      end

    total_requested = length(uncached_ids)

    Logger.info("Found #{total_requested} uncached games to fetch")

    results = fetch_and_cache(uncached_ids)

    summary = %{
      "total_requested" => total_requested,
      "total_cached" => results.cached_count,
      "total_failed" => results.failed_count,
      "end_of_list" => end_of_list?,
      "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Logger.info("PrecacheWorker complete: #{inspect(summary)}")

    record_results(job.id, job.meta, summary)

    Phoenix.PubSub.broadcast(Web.PubSub, "dispatch:jobs", :job_updated)

    :ok
  end

  defp fetch_and_cache([]), do: %{cached_count: 0, failed_count: 0}

  defp fetch_and_cache(ids) do
    ids
    |> Enum.chunk_every(@chunk_size)
    |> Enum.with_index()
    |> Enum.reduce(%{cached_count: 0, failed_count: 0}, fn {chunk, index}, acc ->
      if index > 0, do: :timer.sleep(@rate_limit_delay_ms)

      Logger.info("Fetching chunk #{index + 1}: #{length(chunk)} games")

      case fetch_chunk(chunk) do
        {:ok, count} ->
          %{acc | cached_count: acc.cached_count + count}

        {:error, failed_count} ->
          %{acc | failed_count: acc.failed_count + failed_count}
      end
    end)
  end

  defp fetch_chunk(chunk_ids) do
    with {:ok, things} <- BggGateway.things(chunk_ids) do
      results =
        Enum.map(things, fn thing ->
          case Thing.upsert_thing(thing) do
            {:ok, _} -> :ok
            {:error, reason} ->
              Logger.warning("Failed to upsert thing #{thing.id}: #{inspect(reason)}")
              :error
          end
        end)

      success_count = Enum.count(results, &(&1 == :ok))
      {:ok, success_count}
    else
      {:error, reason} ->
        Logger.warning("BGG API call failed for chunk: #{inspect(reason)}")
        {:error, length(chunk_ids)}
    end
  end

  defp record_results(job_id, existing_meta, summary) do
    Oban.Job
    |> Core.Repo.get!(job_id)
    |> Ecto.Changeset.change(meta: Map.merge(existing_meta, %{"results" => summary}))
    |> Core.Repo.update!()
  rescue
    error ->
      Logger.error("Failed to record job results: #{inspect(error)}")
  end
end
