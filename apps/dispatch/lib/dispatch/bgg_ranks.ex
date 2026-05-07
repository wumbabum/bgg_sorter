defmodule Dispatch.BggRanks do
  @moduledoc """
  Parses the BGG ranks CSV and identifies top-ranked uncached games.
  """

  require Logger

  @csv_path Application.app_dir(:core, "priv/boardgames_ranks.csv")

  @doc """
  Parses the BGG ranks CSV, returning base games sorted by rank.
  Filters out expansions (is_expansion != 0) and unranked games.
  """
  @spec parse_ranks() :: [%{id: String.t(), name: String.t(), rank: integer()}]
  def parse_ranks do
    parse_ranks_from_path(@csv_path)
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

  @doc """
  Returns the top N uncached game IDs sorted by rank.
  Games already freshly cached in the DB are excluded.
  """
  @spec uncached_top_n(non_neg_integer()) :: [String.t()]
  def uncached_top_n(n) do
    all_ids =
      parse_ranks()
      |> Enum.map(& &1.id)

    case Core.BggCacher.get_stale_thing_ids(all_ids) do
      {:ok, stale_ids} ->
        stale_set = MapSet.new(stale_ids)

        # Return top N from ranked list that are stale/uncached
        all_ids
        |> Enum.filter(&MapSet.member?(stale_set, &1))
        |> Enum.take(n)

      {:error, reason} ->
        Logger.error("Failed to get stale thing IDs: #{inspect(reason)}")
        []
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
