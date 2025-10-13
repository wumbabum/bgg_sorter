defmodule Web.SorterTest do
  use ExUnit.Case, async: true

  alias Web.Sorter
  alias Core.Schemas.Thing

  # Test data setup
  defp create_test_things do
    [
      %Thing{
        id: "1",
        type: "boardgame",
        primary_name: "Wingspan",
        minplayers: "1",
        maxplayers: "5",
        average: "8.1",
        averageweight: "2.44"
      },
      %Thing{
        id: "2", 
        type: "boardgame",
        primary_name: "Azul",
        minplayers: "2",
        maxplayers: "4", 
        average: "7.9",
        averageweight: "1.78"
      },
      %Thing{
        id: "3",
        type: "boardgame",
        primary_name: "7 Wonders",
        minplayers: "3",
        maxplayers: "7",
        average: "7.7",
        averageweight: "2.33"
      },
      %Thing{
        id: "4",
        type: "boardgame", 
        primary_name: "Gloomhaven",
        minplayers: "1",
        maxplayers: "4",
        average: "8.8",
        averageweight: "3.86"
      },
      %Thing{
        id: "5",
        type: "boardgame",
        primary_name: "Ticket to Ride",
        minplayers: "2",
        maxplayers: "5",
        average: "7.4",
        averageweight: "1.84"
      }
    ]
  end

  describe "sort_by/3 with primary_name" do
    test "sorts by primary_name ascending by default" do
      things = create_test_things()
      
      sorted = Sorter.sort_by(things, :primary_name)
      names = Enum.map(sorted, & &1.primary_name)
      
      assert names == ["7 Wonders", "Azul", "Gloomhaven", "Ticket to Ride", "Wingspan"]
    end

    test "sorts by primary_name ascending explicitly" do
      things = create_test_things()
      
      sorted = Sorter.sort_by(things, :primary_name, :asc)
      names = Enum.map(sorted, & &1.primary_name)
      
      assert names == ["7 Wonders", "Azul", "Gloomhaven", "Ticket to Ride", "Wingspan"]
    end

    test "sorts by primary_name descending" do
      things = create_test_things()
      
      sorted = Sorter.sort_by(things, :primary_name, :desc)
      names = Enum.map(sorted, & &1.primary_name)
      
      assert names == ["Wingspan", "Ticket to Ride", "Gloomhaven", "Azul", "7 Wonders"]
    end

    test "handles nil primary_name values" do
      things = [
        %Thing{id: "1", type: "boardgame", primary_name: "Azul"},
        %Thing{id: "2", type: "boardgame", primary_name: nil},
        %Thing{id: "3", type: "boardgame", primary_name: "7 Wonders"}
      ]
      
      sorted = Sorter.sort_by(things, :primary_name)
      names = Enum.map(sorted, & &1.primary_name)
      
      assert names == [nil, "7 Wonders", "Azul"]
    end
  end

  describe "sort_by/3 with players" do
    test "sorts by minimum players ascending" do
      things = create_test_things()
      
      sorted = Sorter.sort_by(things, :players)
      min_players = Enum.map(sorted, & &1.minplayers)
      
      # Should be ordered by minplayers: "1", "1", "2", "2", "3"
      assert min_players == ["1", "1", "2", "2", "3"]
    end

    test "sorts by minimum players descending" do
      things = create_test_things()
      
      sorted = Sorter.sort_by(things, :players, :desc)
      min_players = Enum.map(sorted, & &1.minplayers)
      
      # Should be ordered by minplayers descending: "3", "2", "2", "1", "1"
      assert min_players == ["3", "2", "2", "1", "1"]
    end

    test "handles nil and invalid minplayers values" do
      things = [
        %Thing{id: "1", type: "boardgame", minplayers: "2"},
        %Thing{id: "2", type: "boardgame", minplayers: nil},
        %Thing{id: "3", type: "boardgame", minplayers: "invalid"},
        %Thing{id: "4", type: "boardgame", minplayers: "1"}
      ]
      
      sorted = Sorter.sort_by(things, :players)
      min_players = Enum.map(sorted, & &1.minplayers)
      
      # nil and "invalid" should be treated as 0, so come first
      assert min_players == [nil, "invalid", "1", "2"]
    end
  end

  describe "sort_by/3 with average rating" do
    test "sorts by average rating ascending" do
      things = create_test_things()
      
      sorted = Sorter.sort_by(things, :average)
      ratings = Enum.map(sorted, & &1.average)
      
      assert ratings == ["7.4", "7.7", "7.9", "8.1", "8.8"]
    end

    test "sorts by average rating descending" do
      things = create_test_things()
      
      sorted = Sorter.sort_by(things, :average, :desc)
      ratings = Enum.map(sorted, & &1.average)
      
      assert ratings == ["8.8", "8.1", "7.9", "7.7", "7.4"]
    end

    test "handles nil and invalid average values" do
      things = [
        %Thing{id: "1", type: "boardgame", average: "8.5"},
        %Thing{id: "2", type: "boardgame", average: nil},
        %Thing{id: "3", type: "boardgame", average: "invalid"},
        %Thing{id: "4", type: "boardgame", average: "7.2"}
      ]
      
      sorted = Sorter.sort_by(things, :average)
      ratings = Enum.map(sorted, & &1.average)
      
      # nil and "invalid" should be treated as 0.0, so come first
      assert ratings == [nil, "invalid", "7.2", "8.5"]
    end
  end

  describe "sort_by/3 with average weight" do
    test "sorts by average weight ascending" do
      things = create_test_things()
      
      sorted = Sorter.sort_by(things, :averageweight)
      weights = Enum.map(sorted, & &1.averageweight)
      
      assert weights == ["1.78", "1.84", "2.33", "2.44", "3.86"]
    end

    test "sorts by average weight descending" do
      things = create_test_things()
      
      sorted = Sorter.sort_by(things, :averageweight, :desc)
      weights = Enum.map(sorted, & &1.averageweight)
      
      assert weights == ["3.86", "2.44", "2.33", "1.84", "1.78"]
    end

    test "handles nil and invalid averageweight values" do
      things = [
        %Thing{id: "1", type: "boardgame", averageweight: "2.5"},
        %Thing{id: "2", type: "boardgame", averageweight: nil},
        %Thing{id: "3", type: "boardgame", averageweight: "invalid"},
        %Thing{id: "4", type: "boardgame", averageweight: "1.8"}
      ]
      
      sorted = Sorter.sort_by(things, :averageweight)
      weights = Enum.map(sorted, & &1.averageweight)
      
      # nil and "invalid" should be treated as 0.0, so come first
      assert weights == [nil, "invalid", "1.8", "2.5"]
    end
  end

  describe "sort_by/3 edge cases" do
    test "handles empty list" do
      sorted = Sorter.sort_by([], :primary_name)
      
      assert sorted == []
    end

    test "handles single item list" do
      things = [%Thing{id: "1", type: "boardgame", primary_name: "Solo Game"}]
      
      sorted = Sorter.sort_by(things, :primary_name)
      
      assert sorted == things
    end

    test "maintains order for identical values" do
      things = [
        %Thing{id: "1", type: "boardgame", primary_name: "Same Name", average: "7.5"},
        %Thing{id: "2", type: "boardgame", primary_name: "Same Name", average: "7.5"},
        %Thing{id: "3", type: "boardgame", primary_name: "Same Name", average: "7.5"}
      ]
      
      sorted_by_name = Sorter.sort_by(things, :primary_name)
      sorted_by_rating = Sorter.sort_by(things, :average)
      
      # Order should be preserved for identical values
      assert Enum.map(sorted_by_name, & &1.id) == ["1", "2", "3"]
      assert Enum.map(sorted_by_rating, & &1.id) == ["1", "2", "3"]
    end
  end
end