defmodule Dispatch.BggRanks do
  @moduledoc """
  Parses the BGG ranks CSV and identifies top-ranked uncached games.
  """

  require Logger

  # Resolve the CSV path at runtime, not compile time. Using a module
  # attribute here would bake the build-host's _build/<env>/lib/core/priv/...
  # path into the BEAM file; that path does not exist at runtime in a Mix
  # release (the priv files are copied to lib/core-<vsn>/priv/...), so the
  # PrecacheWorker would crash immediately on the deployed host with
  # File.Error: no such file or directory.
  defp csv_path, do: Application.app_dir(:core, "priv/boardgames_ranks.csv")

  @doc """
  Parses the BGG ranks CSV, returning base games sorted by rank.
  Filters out expansions (is_expansion != 0) and unranked games.
  """
  @spec parse_ranks() :: [%{id: String.t(), name: String.t(), rank: integer()}]
  def parse_ranks do
    parse_ranks_from_path(csv_path())
  end

  @doc """
  Parses ranks from a specific file path. Useful for testing.
  """
  @spec parse_ranks_from_path(String.t()) :: [%{id: String.t(), name: String.t(), rank: integer()}]
  def parse_ranks_from_path(path) do
    case File.read(path) do
      {:ok, contents} ->
        contents
        |> String.split("\n", trim: true)
        # skip header
        |> Enum.drop(1)
        |> Enum.flat_map(&parse_row/1)
        |> Enum.sort_by(& &1.rank, :asc)

      {:error, reason} ->
        Logger.error("Failed to read BGG ranks CSV at #{path}: #{inspect(reason)}")
        []
    end
  end

  @batch_size 100

  @doc """
  Returns the top N uncached game IDs sorted by rank.
  Streams the CSV in batches of #{@batch_size}, querying the DB for each batch
  to find uncached IDs. Stops as soon as N uncached IDs are accumulated.
  Returns {:ok, ids} or {:error, :end_of_list} if the CSV is exhausted.
  """
  @spec uncached_top_n(non_neg_integer()) :: {:ok, [String.t()]} | {:error, :end_of_list}
  def uncached_top_n(n), do: uncached_top_n_from_path(csv_path(), n)

  @doc "Same as uncached_top_n/1 but reads from a specific path. Useful for testing."
  @spec uncached_top_n_from_path(String.t(), non_neg_integer()) ::
          {:ok, [String.t()]} | {:error, :end_of_list}
  def uncached_top_n_from_path(path, n) do
    path
    |> File.stream!()
    |> Stream.drop(1)
    |> Stream.flat_map(&parse_row/1)
    |> Stream.map(& &1.id)
    |> Stream.chunk_every(@batch_size)
    |> Enum.reduce_while([], fn batch_ids, acc ->
      case Core.BggCacher.get_stale_thing_ids(batch_ids) do
        {:ok, stale_ids} ->
          stale_set = MapSet.new(stale_ids)

          # Keep only uncached IDs, preserving rank order from the batch
          new_uncached =
            batch_ids
            |> Enum.filter(&MapSet.member?(stale_set, &1))

          updated_acc = acc ++ new_uncached

          if length(updated_acc) >= n do
            {:halt, {:ok, Enum.take(updated_acc, n)}}
          else
            {:cont, updated_acc}
          end

        {:error, reason} ->
          Logger.error("Failed to get stale thing IDs: #{inspect(reason)}")
          {:cont, acc}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, ids}
      acc when is_list(acc) and acc != [] -> {:ok, acc}
      [] -> {:error, :end_of_list}
    end
  end

  # Parse a single CSV row into a map, or [] if invalid/expansion/unranked
  defp parse_row(row) do
    # Handle quoted CSV fields (names can contain commas)
    fields = split_csv_row(row)

    with [id, name, _year, rank_str, _bayes, _avg, _rated, is_expansion | _rest] <- fields,
         {rank, _} <- Integer.parse(rank_str),
         true <- is_expansion in ["0", ""] do
      [%{id: id, name: unquote_csv(name), rank: rank}]
    else
      _ -> []
    end
  end

  # Split a CSV row respecting quoted fields
  defp split_csv_row(row) do
    row
    |> String.trim()
    |> do_split_csv([], "")
    |> Enum.reverse()
  end

  defp do_split_csv("", acc, current), do: [current | acc]

  defp do_split_csv("\"" <> rest, acc, current) do
    {quoted, remainder} = consume_quoted(rest, current)
    do_split_csv(remainder, acc, quoted)
  end

  defp do_split_csv("," <> rest, acc, current) do
    do_split_csv(rest, [current | acc], "")
  end

  defp do_split_csv(<<char::utf8, rest::binary>>, acc, current) do
    do_split_csv(rest, acc, current <> <<char::utf8>>)
  end

  defp consume_quoted("\"" <> rest, acc), do: {acc, rest}

  defp consume_quoted(<<char::utf8, rest::binary>>, acc) do
    consume_quoted(rest, acc <> <<char::utf8>>)
  end

  defp consume_quoted("", acc), do: {acc, ""}

  defp unquote_csv("\"" <> rest) do
    String.trim_trailing(rest, "\"")
  end

  defp unquote_csv(value), do: value
end
