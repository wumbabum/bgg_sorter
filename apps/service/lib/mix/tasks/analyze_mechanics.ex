defmodule Mix.Tasks.AnalyzeMechanics do
  @shortdoc "Analyze BGG mechanics data from top 1000 board games"
  @moduledoc """
  Analyzes mechanics data from the top 1000 board games from boardgames_ranks.csv
  using Core.BggGateway.things() to make chunked, rate-limited requests to BGG API.

  Outputs the top 100 mechanics ranked by frequency to mechanics_count.csv.

  ## Usage

      mix analyze_mechanics

  ## Rate Limiting & Chunking

  The task processes games in chunks of 20 (BGG API limit) with 4-second delays
  between chunks to respect BGG API limits. Processing all 1000 games will take
  approximately 3-4 minutes (50 chunks × 4 seconds = ~200 seconds).

  ## Output

  Creates mechanics_count.csv with columns:
  - mechanic: The name of the mechanic
  - count: Number of games in top 1000 that use this mechanic
  - percentage: Percentage of top 1000 games using this mechanic
  """

  use Mix.Task
  require Logger
  alias Core.BggGateway

  # 4 second delay between requests
  @rate_limit_delay 4000

  @impl Mix.Task
  def run(_args) do
    Logger.info("Starting BGG mechanics analysis for top 1000 games...")

    # Start the core application
    Mix.Task.run("app.start", ["--only", "core"])

    case process_games() do
      {:ok, mechanics_count} ->
        write_output_file(mechanics_count)
        Logger.info("Analysis complete! Results written to mechanics_count.csv")

      {:error, reason} ->
        Logger.error("Analysis failed: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp process_games do
    with {:ok, game_ids} <- read_csv_file(),
         {:ok, games_mechanics} <- fetch_mechanics_data(game_ids) do
      mechanics_count = count_mechanics(games_mechanics)
      {:ok, mechanics_count}
    else
      error -> error
    end
  end

  defp read_csv_file do
    # Look for the CSV file in the umbrella root
    # __DIR__ points to apps/service/lib/mix/tasks/, so we need to go up 5 levels to get to umbrella root
    umbrella_root = Path.join([__DIR__, "..", "..", "..", "..", ".."])
    csv_path = Path.join(umbrella_root, "boardgames_ranks.csv")

    case File.exists?(csv_path) do
      true ->
        Logger.info("Reading #{csv_path}...")

        game_ids =
          csv_path
          |> File.stream!()
          # Skip header row
          |> Stream.drop(1)
          # Take top 1000 games
          |> Stream.take(1000)
          |> Stream.map(&String.trim/1)
          |> Stream.map(&extract_game_id/1)
          |> Stream.filter(&(&1 != nil))
          |> Enum.to_list()

        Logger.info("Found #{length(game_ids)} game IDs to process")
        {:ok, game_ids}

      false ->
        Logger.error("Could not find boardgames_ranks.csv in current directory")
        {:error, :file_not_found}
    end
  end

  defp extract_game_id(csv_line) do
    case String.split(csv_line, ",", parts: 2) do
      [id | _] when id != "" ->
        case Integer.parse(id) do
          {int_id, ""} -> to_string(int_id)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp fetch_mechanics_data(game_ids) do
    total_games = length(game_ids)
    chunks = Enum.chunk_every(game_ids, 20)
    total_chunks = length(chunks)

    Logger.info(
      "Fetching mechanics data for #{total_games} games in #{total_chunks} chunks of 20..."
    )

    Logger.info(
      "This will take approximately #{div(total_chunks * @rate_limit_delay, 1000)} seconds due to rate limiting"
    )

    chunks
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {chunk, chunk_index}, {:ok, acc} ->
      Logger.info(
        "Processing chunk #{chunk_index}/#{total_chunks} (games #{(chunk_index - 1) * 20 + 1} to #{min(chunk_index * 20, total_games)})"
      )

      case fetch_chunk_mechanics(chunk) do
        {:ok, chunk_results} ->
          # Rate limit: wait between chunks (except for the last one)
          if chunk_index < total_chunks do
            Process.sleep(@rate_limit_delay)
          end

          {:cont, {:ok, chunk_results ++ acc}}

        {:error, reason} ->
          Logger.warning("Failed to fetch mechanics for chunk #{chunk_index}: #{inspect(reason)}")
          # Continue processing even if individual chunks fail

          if chunk_index < total_chunks do
            Process.sleep(@rate_limit_delay)
          end

          {:cont, {:ok, acc}}
      end
    end)
  end

  defp fetch_chunk_mechanics(game_ids) do
    case BggGateway.things(game_ids) do
      {:ok, [_ | _] = things} ->
        # Create a map of game_id -> mechanics for each thing returned
        chunk_results =
          Enum.map(things, fn thing ->
            game_id = thing.id
            mechanics = Map.get(thing, :raw_mechanics, [])
            {game_id, mechanics}
          end)

        Logger.debug(
          "Successfully fetched #{length(things)} games from chunk of #{length(game_ids)}"
        )

        {:ok, chunk_results}

      {:ok, []} ->
        Logger.warning("No data returned for game IDs: #{Enum.join(game_ids, ", ")}")
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp count_mechanics(games_mechanics) do
    Logger.info("Analyzing mechanics data from #{length(games_mechanics)} games...")

    all_mechanics =
      games_mechanics
      |> Enum.flat_map(fn {_game_id, mechanics} -> mechanics end)
      |> Enum.frequencies()

    total_games = length(games_mechanics)

    all_mechanics
    |> Enum.map(fn {mechanic, count} ->
      percentage = Float.round(count / total_games * 100, 2)
      %{mechanic: mechanic, count: count, percentage: percentage}
    end)
    |> Enum.sort_by(& &1.count, :desc)

    # |> Enum.take(100)  # Top 100 mechanics
  end

  defp write_output_file(mechanics_count) do
    # Write output to umbrella root
    umbrella_root = Path.join([__DIR__, "..", "..", "..", "..", ".."])
    output_path = Path.join(umbrella_root, "mechanics_count.csv")
    Logger.info("Writing results to #{output_path}")

    csv_content = [
      "mechanic,count,percentage\n"
      | Enum.map(mechanics_count, fn %{mechanic: mechanic, count: count, percentage: percentage} ->
          # Escape commas and quotes in mechanic names
          escaped_mechanic =
            mechanic
            |> String.replace("\"", "\"\"")
            |> then(fn m -> if String.contains?(m, ","), do: "\"#{m}\"", else: m end)

          "#{escaped_mechanic},#{count},#{percentage}\n"
        end)
    ]

    File.write!(output_path, csv_content)

    # Log summary
    Logger.info("Top 10 mechanics:")

    mechanics_count
    |> Enum.take(10)
    |> Enum.with_index(1)
    |> Enum.each(fn {%{mechanic: mechanic, count: count, percentage: percentage}, rank} ->
      Logger.info("#{rank}. #{mechanic}: #{count} games (#{percentage}%)")
    end)
  end
end
