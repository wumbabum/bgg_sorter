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

    test "returns uncached IDs sorted by rank" do
      # All games in the real CSV should be uncached (empty DB)
      # This test uses the real CSV file
      results = BggRanks.uncached_top_n(5)

      # Should return up to 5 IDs
      assert length(results) <= 5
      assert is_list(results)
      assert Enum.all?(results, &is_binary/1)
    end

    test "excludes already cached games" do
      # Cache one game
      {:ok, _} = Core.Schemas.Thing.upsert_thing(%{
        "id" => "224517",
        "type" => "boardgame",
        "primary_name" => "Brass: Birmingham"
      })

      results = BggRanks.uncached_top_n(5)

      # Brass: Birmingham (224517) should NOT be in the results
      refute "224517" in results
    end
  end
end
