defmodule Core.Schemas.ThingMechanicsTest do
  use Core.DataCase, async: true

  alias Core.Schemas.{Thing, Mechanic, ThingMechanic}
  alias Core.Repo

  describe "upsert_thing/1 with mechanics processing" do
    test "creates mechanics and associations when upserting thing with raw_mechanics" do
      # Test data with mechanics (based on real Brass: Birmingham response)
      thing_params = %{
        "id" => "224517",
        "type" => "boardgame",
        "primary_name" => "Brass: Birmingham",
        "yearpublished" => "2018",
        "raw_mechanics" => [
          "Chaining",
          "End Game Bonuses", 
          "Hand Management",
          "Income",
          "Tile Placement"
        ]
      }

      # Initially no mechanics or associations should exist
      assert Repo.aggregate(Mechanic, :count, :id) == 0
      assert Repo.aggregate(ThingMechanic, :count, :id) == 0

      # Upsert the thing
      assert {:ok, upserted_thing} = Thing.upsert_thing(thing_params)

      # Thing should have mechanics checksum
      assert upserted_thing.mechanics_checksum != nil
      assert is_binary(upserted_thing.mechanics_checksum)

      # Mechanics should be created in the database
      mechanics_count = Repo.aggregate(Mechanic, :count, :id)
      assert mechanics_count == 5

      # ThingMechanic associations should be created
      thing_mechanics_count = Repo.aggregate(ThingMechanic, :count, :id)
      assert thing_mechanics_count == 5

      # Verify mechanic names and slugs
      all_mechanics = Repo.all(Mechanic)
      mechanic_names = Enum.map(all_mechanics, & &1.name) |> Enum.sort()
      expected_names = ["Chaining", "End Game Bonuses", "Hand Management", "Income", "Tile Placement"]
      assert mechanic_names == expected_names

      # Verify associations work
      thing_with_mechanics = Repo.get(Thing, "224517") |> Repo.preload(:mechanics)
      associated_mechanic_names = 
        thing_with_mechanics.mechanics
        |> Enum.map(& &1.name)
        |> Enum.sort()
      
      assert associated_mechanic_names == expected_names
    end

    test "skips mechanics processing when no raw_mechanics provided" do
      thing_params = %{
        "id" => "123456",
        "type" => "boardgame",
        "primary_name" => "Simple Game"
      }

      assert {:ok, upserted_thing} = Thing.upsert_thing(thing_params)

      # Should have nil checksum when no mechanics
      assert upserted_thing.mechanics_checksum == nil

      # No mechanics should be created
      assert Repo.aggregate(Mechanic, :count, :id) == 0
      assert Repo.aggregate(ThingMechanic, :count, :id) == 0
    end

    test "skips mechanics processing when raw_mechanics is empty list" do
      thing_params = %{
        "id" => "654321",
        "type" => "boardgame",
        "primary_name" => "Game with Empty Mechanics",
        "raw_mechanics" => []
      }

      assert {:ok, upserted_thing} = Thing.upsert_thing(thing_params)

      # Should have nil checksum when empty mechanics
      assert upserted_thing.mechanics_checksum == nil

      # No mechanics should be created
      assert Repo.aggregate(Mechanic, :count, :id) == 0
      assert Repo.aggregate(ThingMechanic, :count, :id) == 0
    end

    test "handles duplicate mechanics correctly" do
      # First thing with some mechanics
      thing1_params = %{
        "id" => "111111",
        "type" => "boardgame",
        "primary_name" => "Game One",
        "raw_mechanics" => ["Hand Management", "Tile Placement"]
      }

      # Second thing with overlapping mechanics
      thing2_params = %{
        "id" => "222222",
        "type" => "boardgame",
        "primary_name" => "Game Two", 
        "raw_mechanics" => ["Hand Management", "Worker Placement", "Engine Building"]
      }

      # Upsert both things
      assert {:ok, _thing1} = Thing.upsert_thing(thing1_params)
      assert {:ok, _thing2} = Thing.upsert_thing(thing2_params)

      # Should have unique mechanics (no duplicates)
      mechanics_count = Repo.aggregate(Mechanic, :count, :id)
      assert mechanics_count == 4  # Hand Management, Tile Placement, Worker Placement, Engine Building

      # Should have correct associations count  
      thing_mechanics_count = Repo.aggregate(ThingMechanic, :count, :id)
      assert thing_mechanics_count == 5  # 2 for thing1 + 3 for thing2

      # Verify "Hand Management" mechanic is shared
      hand_management = Repo.get_by(Mechanic, name: "Hand Management")
      assert hand_management != nil

      # Both things should be associated with the same "Hand Management" mechanic
      thing1_associations = Repo.all(from tm in ThingMechanic, where: tm.thing_id == "111111")
      thing2_associations = Repo.all(from tm in ThingMechanic, where: tm.thing_id == "222222")

      thing1_mechanic_ids = Enum.map(thing1_associations, & &1.mechanic_id)
      thing2_mechanic_ids = Enum.map(thing2_associations, & &1.mechanic_id)

      assert hand_management.id in thing1_mechanic_ids
      assert hand_management.id in thing2_mechanic_ids
    end

    test "updates mechanics when thing is updated with different mechanics" do
      # Initial thing with mechanics
      initial_params = %{
        "id" => "333333",
        "type" => "boardgame",
        "primary_name" => "Evolving Game",
        "raw_mechanics" => ["Hand Management", "Tile Placement"]
      }

      assert {:ok, initial_thing} = Thing.upsert_thing(initial_params)
      initial_checksum = initial_thing.mechanics_checksum

      # Update with different mechanics
      updated_params = %{
        "id" => "333333",
        "type" => "boardgame", 
        "primary_name" => "Evolving Game",
        "raw_mechanics" => ["Worker Placement", "Engine Building", "Deck Building"]
      }

      assert {:ok, updated_thing} = Thing.upsert_thing(updated_params)
      updated_checksum = updated_thing.mechanics_checksum

      # Checksum should be different
      refute initial_checksum == updated_checksum

      # Should have new mechanics count (previous + new - shared)
      # Initial: Hand Management, Tile Placement (2)
      # Updated: Worker Placement, Engine Building, Deck Building (3)
      # Total unique: 5 (no overlap)
      mechanics_count = Repo.aggregate(Mechanic, :count, :id)
      assert mechanics_count == 5

      # Thing should only be associated with new mechanics (3)
      thing_mechanics_count = 
        from(tm in ThingMechanic, where: tm.thing_id == "333333")
        |> Repo.aggregate(:count, :id)
      assert thing_mechanics_count == 3

      # Verify correct associations
      thing_with_mechanics = Repo.get(Thing, "333333") |> Repo.preload(:mechanics)
      associated_names = 
        thing_with_mechanics.mechanics
        |> Enum.map(& &1.name)
        |> Enum.sort()
      
      expected_names = ["Deck Building", "Engine Building", "Worker Placement"]
      assert associated_names == expected_names
    end

    test "skips mechanics update when checksum matches (optimization)" do
      # Create thing with mechanics
      params = %{
        "id" => "444444",
        "type" => "boardgame",
        "primary_name" => "Unchanged Game",
        "raw_mechanics" => ["Hand Management", "Tile Placement"]
      }

      assert {:ok, initial_thing} = Thing.upsert_thing(params)
      initial_checksum = initial_thing.mechanics_checksum
      initial_updated_at = initial_thing.updated_at

      :timer.sleep(100)  # Ensure timestamp difference

      # Upsert again with same mechanics (different order to test sorting)
      same_params = %{
        "id" => "444444",
        "type" => "boardgame",
        "primary_name" => "Unchanged Game",
        "raw_mechanics" => ["Tile Placement", "Hand Management"]  # Different order
      }

      assert {:ok, updated_thing} = Thing.upsert_thing(same_params)
      updated_checksum = updated_thing.mechanics_checksum

      # Checksum should be the same (order doesn't matter)
      assert initial_checksum == updated_checksum

      # Thing should still have last_cached updated but mechanics unchanged
      assert DateTime.compare(updated_thing.last_cached, initial_thing.last_cached) in [:gt, :eq]

      # Associations count should remain the same
      thing_mechanics_count = 
        from(tm in ThingMechanic, where: tm.thing_id == "444444")
        |> Repo.aggregate(:count, :id)
      assert thing_mechanics_count == 2
    end

    test "handles mechanics with special characters and normalization" do
      params = %{
        "id" => "555555",
        "type" => "boardgame",
        "primary_name" => "Special Characters Game",
        "raw_mechanics" => [
          "  Hand Management  ",      # Leading/trailing spaces
          "Multi-Use Cards",          # Hyphens
          "Co-operative Play",        # Hyphens
          "Action/Movement Programming" # Forward slash
        ]
      }

      assert {:ok, thing} = Thing.upsert_thing(params)

      # Mechanics should be created with normalized names
      all_mechanics = Repo.all(Mechanic)
      mechanic_names = Enum.map(all_mechanics, & &1.name) |> Enum.sort()
      
      expected_names = [
        "Action/Movement Programming",
        "Co-operative Play", 
        "Hand Management",  # Spaces should be trimmed
        "Multi-Use Cards"
      ]
      assert mechanic_names == expected_names

      # Verify slugs are generated correctly
      hand_management = Repo.get_by(Mechanic, name: "Hand Management")
      assert hand_management.slug == "hand-management"

      multi_use = Repo.get_by(Mechanic, name: "Multi-Use Cards")
      assert multi_use.slug == "multi-use-cards"

      cooperative = Repo.get_by(Mechanic, name: "Co-operative Play")
      assert cooperative.slug == "co-operative-play"
    end
  end
end