defmodule Dispatch.BggRanksTest do
  use ExUnit.Case, async: false

  alias Dispatch.BggRanks

  @sample_csv Path.join([__DIR__, "..", "support", "sample_ranks.csv"])

  @moduletag :capture_log

  describe "parse_ranks_from_path/1" do
    test "parses base games sorted by rank" do
      results = BggRanks.parse_ranks_from_path(@sample_csv)

      assert length(results) == 4
      assert Enum.map(results, & &1.rank) == [1, 2, 3, 4]
    end

    test "filters out expansions" do
      results = BggRanks.parse_ranks_from_path(@sample_csv)
      ids = Enum.map(results, & &1.id)

      # "Some Expansion" (id 999999, is_expansion=1) should be excluded
      refute "999999" in ids
    end

    test "filters out unranked games" do
      results = BggRanks.parse_ranks_from_path(@sample_csv)
      ids = Enum.map(results, & &1.id)

      # "Unranked Game" (id 888888, rank="") should be excluded
      refute "888888" in ids
    end

    test "handles quoted names with commas" do
      results = BggRanks.parse_ranks_from_path(@sample_csv)
      brass = Enum.find(results, &(&1.id == "224517"))

      assert brass.name == "Brass: Birmingham"
    end

    test "returns correct fields" do
      results = BggRanks.parse_ranks_from_path(@sample_csv)
      first = hd(results)

      assert first.id == "224517"
      assert first.name == "Brass: Birmingham"
      assert first.rank == 1
    end

    test "returns empty list for missing file" do
      assert [] == BggRanks.parse_ranks_from_path("/nonexistent/path.csv")
    end
  end

  describe "uncached_top_n/1" do
    setup do
      pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Core.Repo, shared: false)
      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
      :ok
    end

    test "returns {:ok, ids} with uncached IDs sorted by rank" do
      assert {:ok, results} = BggRanks.uncached_top_n(5)

      assert length(results) <= 5
      assert Enum.all?(results, &is_binary/1)
    end

    test "excludes already cached games" do
      {:ok, _} = Core.Schemas.Thing.upsert_thing(%{
        "id" => "224517",
        "type" => "boardgame",
        "primary_name" => "Brass: Birmingham"
      })

      assert {:ok, results} = BggRanks.uncached_top_n(5)

      refute "224517" in results
    end

    test "returns {:error, :end_of_list} when all games are cached" do
      # Use the sample CSV which has only 4 base games
      # Cache all 4
      for {id, name} <- [{"224517", "Brass"}, {"342942", "Ark Nova"}, {"161936", "Pandemic"}, {"174430", "Gloomhaven"}] do
        {:ok, _} = Core.Schemas.Thing.upsert_thing(%{"id" => id, "type" => "boardgame", "primary_name" => name})
      end

      assert {:error, :end_of_list} = BggRanks.uncached_top_n_from_path(@sample_csv, 5)
    end

    test "skips cached games and continues scanning for uncached ones" do
      # Cache the #1 ranked game
      {:ok, _} = Core.Schemas.Thing.upsert_thing(%{
        "id" => "224517",
        "type" => "boardgame",
        "primary_name" => "Brass: Birmingham"
      })

      assert {:ok, results} = BggRanks.uncached_top_n_from_path(@sample_csv, 3)

      # Should have 3 uncached games (skipping Brass)
      assert length(results) == 3
      refute "224517" in results
      # Should start with the next ranked uncached game
      assert hd(results) == "342942"
    end
  end
end
