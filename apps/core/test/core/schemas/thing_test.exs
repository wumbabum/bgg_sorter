defmodule Core.Schemas.ThingTest do
  use ExUnit.Case, async: true

  alias Core.Schemas.Thing

  describe "filter_by/2" do
    setup do
      # Create test things with varied data
      things = [
        %Thing{
          id: "1",
          type: "boardgame",
          primary_name: "Wingspan",
          yearpublished: "2019",
          minplayers: "1",
          maxplayers: "5",
          playingtime: "70",
          minplaytime: "40",
          maxplaytime: "75",
          minage: "10",
          rank: "15",
          averageweight: "2.44",
          description: "A competitive bird-themed strategy game"
        },
        %Thing{
          id: "2",
          type: "boardgame",
          primary_name: "Azul",
          yearpublished: "2017",
          minplayers: "2",
          maxplayers: "4",
          playingtime: "45",
          minplaytime: "30",
          maxplaytime: "45",
          minage: "8",
          rank: "45",
          averageweight: "1.78",
          description: "A beautiful tile-laying puzzle game"
        },
        %Thing{
          id: "3",
          type: "boardgame",
          primary_name: "Gloomhaven",
          yearpublished: "2017",
          minplayers: "1",
          maxplayers: "4",
          playingtime: "120",
          minplaytime: "60",
          maxplaytime: "120",
          minage: "14",
          rank: "1",
          averageweight: "3.86",
          description: "Epic dungeon-crawling campaign game"
        },
        %Thing{
          id: "124742",
          type: "boardgame",
          primary_name: "Android: Netrunner",
          yearpublished: "2012",
          minplayers: "2",
          maxplayers: "2",
          playingtime: "45",
          minplaytime: "20",
          maxplaytime: "60",
          minage: "14",
          rank: "81",
          averageweight: "3.413",
          description: "Welcome to New Angeles, home of the Beanstalk cyberpunk card game"
        },
        %Thing{
          id: "41114",
          type: "boardgame",
          primary_name: "The Resistance",
          yearpublished: "2009",
          minplayers: "5",
          maxplayers: "10",
          playingtime: "30",
          minplaytime: "20",
          maxplaytime: "30",
          minage: "13",
          rank: "437",
          averageweight: "1.591",
          description: "The Empire must fall. Our mission must succeed social deduction game"
        }
      ]

      %{things: things}
    end

    test "returns all things when filters is empty map", %{things: things} do
      assert Thing.filter_by(things, %{}) == things
    end

    test "returns all things when no filters argument provided", %{things: things} do
      assert Thing.filter_by(things) == things
    end

    test "returns all things when filters contain only nil/empty values", %{things: things} do
      filters = %{primary_name: nil, players: "", rank: nil}
      assert Thing.filter_by(things, filters) == things
    end

    test "filters by primary_name (case insensitive)", %{things: things} do
      # Should match "Wingspan"
      assert [%Thing{primary_name: "Wingspan"}] = Thing.filter_by(things, %{primary_name: "wing"})
      assert [%Thing{primary_name: "Wingspan"}] = Thing.filter_by(things, %{primary_name: "WING"})

      # Should match all five (all contain 'a')
      result = Thing.filter_by(things, %{primary_name: "a"})
      assert length(result) == 5
      assert Enum.any?(result, &(&1.primary_name == "Wingspan"))
      assert Enum.any?(result, &(&1.primary_name == "Azul"))
      assert Enum.any?(result, &(&1.primary_name == "Gloomhaven"))
      assert Enum.any?(result, &(&1.primary_name == "Android: Netrunner"))
      assert Enum.any?(result, &(&1.primary_name == "The Resistance"))
    end

    test "filters by player count", %{things: things} do
      # 2 players: should match Wingspan (1-5), Azul (2-4), Gloomhaven (1-4), Android: Netrunner (2-2)
      assert length(Thing.filter_by(things, %{players: "2"})) == 4

      # 5 players: should match Wingspan (1-5) and The Resistance (5-10)
      result = Thing.filter_by(things, %{players: "5"})
      assert length(result) == 2
      assert Enum.any?(result, &(&1.primary_name == "Wingspan"))
      assert Enum.any?(result, &(&1.primary_name == "The Resistance"))

      # 6 players: should match The Resistance (5-10)
      assert [%Thing{primary_name: "The Resistance"}] = Thing.filter_by(things, %{players: "6"})
    end

    test "filters by playing time (range inclusion)", %{things: things} do
      # Test games that include 45 minutes in their range:
      # - Wingspan: 40-75 min (✓)
      # - Azul: 30-45 min (✓) 
      # - Gloomhaven: 60-120 min (✗)
      # - Android: Netrunner: 20-60 min (✓)
      # - The Resistance: 20-30 min (✗)
      result = Thing.filter_by(things, %{playingtime: "45"})
      assert length(result) == 3
      assert Enum.any?(result, &(&1.primary_name == "Wingspan"))
      assert Enum.any?(result, &(&1.primary_name == "Azul"))
      assert Enum.any?(result, &(&1.primary_name == "Android: Netrunner"))

      # Test games that include 25 minutes in their range:
      # - Wingspan: 40-75 min (✗)
      # - Azul: 30-45 min (✗)
      # - Gloomhaven: 60-120 min (✗) 
      # - Android: Netrunner: 20-60 min (✓)
      # - The Resistance: 20-30 min (✓)
      result = Thing.filter_by(things, %{playingtime: "25"})
      assert length(result) == 2
      assert Enum.any?(result, &(&1.primary_name == "Android: Netrunner"))
      assert Enum.any?(result, &(&1.primary_name == "The Resistance"))

      # Test games that include 100 minutes in their range:
      # Only Gloomhaven: 60-120 min should match
      result = Thing.filter_by(things, %{playingtime: "100"})
      assert length(result) == 1
      assert Enum.any?(result, &(&1.primary_name == "Gloomhaven"))
    end

    test "filters by maximum rank", %{things: things} do
      # Games ranked <= 20: Gloomhaven (1) and Wingspan (15)
      result = Thing.filter_by(things, %{rank: "20"})
      assert length(result) == 2
      assert Enum.any?(result, &(&1.primary_name == "Wingspan"))
      assert Enum.any?(result, &(&1.primary_name == "Gloomhaven"))
    end

    test "filters by weight range", %{things: things} do
      # Min weight 2.0: Wingspan (2.44), Gloomhaven (3.86), Android: Netrunner (3.413)
      result = Thing.filter_by(things, %{averageweight_min: "2.0"})
      assert length(result) == 3
      assert Enum.any?(result, &(&1.primary_name == "Wingspan"))
      assert Enum.any?(result, &(&1.primary_name == "Gloomhaven"))
      assert Enum.any?(result, &(&1.primary_name == "Android: Netrunner"))

      # Max weight 2.5: Wingspan (2.44), Azul (1.78), The Resistance (1.591)
      result = Thing.filter_by(things, %{averageweight_max: "2.5"})
      assert length(result) == 3
      assert Enum.any?(result, &(&1.primary_name == "Wingspan"))
      assert Enum.any?(result, &(&1.primary_name == "Azul"))
      assert Enum.any?(result, &(&1.primary_name == "The Resistance"))
    end

    test "filters by description", %{things: things} do
      # Should match all five (all contain "game")
      result = Thing.filter_by(things, %{description: "game"})
      assert length(result) == 5
      assert Enum.any?(result, &(&1.primary_name == "Wingspan"))
      assert Enum.any?(result, &(&1.primary_name == "Azul"))
      assert Enum.any?(result, &(&1.primary_name == "Gloomhaven"))
      assert Enum.any?(result, &(&1.primary_name == "Android: Netrunner"))
      assert Enum.any?(result, &(&1.primary_name == "The Resistance"))
    end

    test "combines multiple filters", %{things: things} do
      # Test combination of filters:
      # - players: "4" -> Wingspan (1-5), Azul (2-4), Gloomhaven (1-4) support 4 players
      # - playingtime: "50" -> should be within playing time range:
      #   - Wingspan: 40-75 min (✓)
      #   - Azul: 30-45 min (✗) - 50 is outside range
      #   - Gloomhaven: 60-120 min (✗) - 50 is outside range

      result = Thing.filter_by(things, %{players: "4", playingtime: "50"})
      assert length(result) == 1
      assert Enum.any?(result, &(&1.primary_name == "Wingspan"))

      # Test another combination:
      # - players: "3" -> Wingspan (1-5), Azul (2-4), Gloomhaven (1-4) support 3 players
      # - playingtime: "40" -> should be within playing time range:
      #   - Wingspan: 40-75 min (✓)
      #   - Azul: 30-45 min (✓)
      #   - Gloomhaven: 60-120 min (✗)
      result = Thing.filter_by(things, %{players: "3", playingtime: "40"})
      assert length(result) == 2
      assert Enum.any?(result, &(&1.primary_name == "Wingspan"))
      assert Enum.any?(result, &(&1.primary_name == "Azul"))
    end

    test "returns empty list when no things match all filters", %{things: things} do
      # No games support 11 players (The Resistance supports up to 10)
      assert Thing.filter_by(things, %{players: "11"}) == []

      # No games ranked at position 0 (impossible rank)
      assert Thing.filter_by(things, %{rank: "0"}) == []
    end

    test "handles invalid/unparseable data gracefully", %{things: things} do
      # Create thing with invalid data
      invalid_thing = %Thing{
        id: "4",
        type: "boardgame",
        primary_name: "Invalid Game",
        yearpublished: "not_a_year",
        minplayers: "not_a_number",
        maxplayers: "also_not_a_number",
        playingtime: "invalid_time",
        minage: "not_age",
        rank: "not_rank",
        averageweight: "not_weight"
      }

      things_with_invalid = things ++ [invalid_thing]

      # Should include the invalid thing (filtering defaults to true for unparseable data)
      result = Thing.filter_by(things_with_invalid, %{players: "3"})

      # Should include things that actually support 3 players plus the invalid one (defaults to include)
      # 3 players supported by: Wingspan (1-5), Azul (2-4), Gloomhaven (1-4) + invalid one
      # 3 valid games + the invalid one
      assert length(result) == 4
    end

    test "ignores unknown filter keys", %{things: things} do
      # Should ignore unknown filter and return all things
      result = Thing.filter_by(things, %{unknown_filter: "some_value"})
      assert result == things
    end

    test "applies weight defaults when only min provided", %{things: things} do
      # Only min weight provided (2.0), should default max to 5.0
      # Expected: Wingspan (2.44), Gloomhaven (3.86), Android: Netrunner (3.413)
      # Should exclude: Azul (1.78), The Resistance (1.591)
      result = Thing.filter_by(things, %{averageweight_min: "2.0", averageweight_max: nil})
      assert length(result) == 3
      assert Enum.any?(result, &(&1.primary_name == "Wingspan"))
      assert Enum.any?(result, &(&1.primary_name == "Gloomhaven"))
      assert Enum.any?(result, &(&1.primary_name == "Android: Netrunner"))
    end

    test "applies weight defaults when only max provided", %{things: things} do
      # Only max weight provided (2.5), should default min to 0
      # Expected: Wingspan (2.44), Azul (1.78), The Resistance (1.591)
      # Should exclude: Gloomhaven (3.86), Android: Netrunner (3.413)
      result = Thing.filter_by(things, %{averageweight_min: nil, averageweight_max: "2.5"})
      assert length(result) == 3
      assert Enum.any?(result, &(&1.primary_name == "Wingspan"))
      assert Enum.any?(result, &(&1.primary_name == "Azul"))
      assert Enum.any?(result, &(&1.primary_name == "The Resistance"))
    end

    test "applies weight defaults when only min provided with empty string for max", %{
      things: things
    } do
      # Only min weight provided (2.0) with empty string for max, should default max to 5.0
      result = Thing.filter_by(things, %{averageweight_min: "2.0", averageweight_max: ""})
      assert length(result) == 3
      assert Enum.any?(result, &(&1.primary_name == "Wingspan"))
      assert Enum.any?(result, &(&1.primary_name == "Gloomhaven"))
      assert Enum.any?(result, &(&1.primary_name == "Android: Netrunner"))
    end
  end

  describe "generate_mechanics_checksum/1" do
    test "generates consistent checksum for mechanic list" do
      mechanics1 = ["Hand Management", "Worker Placement", "Engine Building"]
      # Different order
      mechanics2 = ["Worker Placement", "Hand Management", "Engine Building"]

      checksum1 = Thing.generate_mechanics_checksum(mechanics1)
      checksum2 = Thing.generate_mechanics_checksum(mechanics2)

      # Should be the same regardless of input order (sorted internally)
      assert checksum1 == checksum2
      assert is_binary(checksum1)
      # SHA256 hex string length
      assert String.length(checksum1) == 64
    end

    test "returns nil for empty list" do
      assert Thing.generate_mechanics_checksum([]) == nil
    end

    test "returns nil for nil input" do
      assert Thing.generate_mechanics_checksum(nil) == nil
    end

    test "generates different checksums for different mechanic lists" do
      mechanics1 = ["Hand Management", "Worker Placement"]
      mechanics2 = ["Hand Management", "Engine Building"]

      checksum1 = Thing.generate_mechanics_checksum(mechanics1)
      checksum2 = Thing.generate_mechanics_checksum(mechanics2)

      refute checksum1 == checksum2
    end

    test "handles single mechanic" do
      mechanics = ["Hand Management"]
      checksum = Thing.generate_mechanics_checksum(mechanics)

      assert is_binary(checksum)
      assert String.length(checksum) == 64
    end
  end
end
