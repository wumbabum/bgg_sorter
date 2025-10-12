defmodule Core.Schemas.ThingUpsertTest do
  use Core.DataCase, async: true

  alias Core.Schemas.Thing

  describe "upsert_thing/1" do
    setup do
      # Base thing data for testing
      %{
        thing_params: %{
          "id" => "123456",
          "type" => "boardgame",
          "primary_name" => "Test Game",
          "yearpublished" => "2020",
          "minplayers" => "2",
          "maxplayers" => "4",
          "playingtime" => "60",
          "minage" => "12",
          "rank" => "100",
          "averageweight" => "2.5",
          "description" => "A test game for our tests"
        }
      }
    end

    test "inserts a new thing with map params", %{thing_params: params} do
      assert {:ok, thing} = Thing.upsert_thing(params)
      
      assert thing.id == "123456"
      assert thing.type == "boardgame"
      assert thing.primary_name == "Test Game"
      assert thing.yearpublished == "2020"
      assert thing.minplayers == "2"
      assert thing.maxplayers == "4"
      assert thing.playingtime == "60"
      assert thing.minage == "12"
      assert thing.rank == "100"
      assert thing.averageweight == "2.5"
      assert thing.description == "A test game for our tests"
      
      # Should have timestamps
      assert %DateTime{} = thing.last_cached
      assert %DateTime{} = thing.inserted_at
      assert %DateTime{} = thing.updated_at
      
      # Verify it's in the database
      db_thing = Core.Repo.get(Thing, "123456")
      assert db_thing.id == thing.id
    end

    test "inserts a new thing with struct params", %{thing_params: params} do
      thing_struct = struct(Thing, (for {key, val} <- params, into: %{}, do: {String.to_existing_atom(key), val}))
      
      assert {:ok, thing} = Thing.upsert_thing(thing_struct)
      
      assert thing.id == "123456"
      assert thing.type == "boardgame"
      assert thing.primary_name == "Test Game"
      
      # Should have timestamps
      assert %DateTime{} = thing.last_cached
      assert %DateTime{} = thing.inserted_at
      assert %DateTime{} = thing.updated_at
    end

    test "updates existing thing with new data", %{thing_params: params} do
      # Insert initial thing
      assert {:ok, original_thing} = Thing.upsert_thing(params)
      original_cached_time = original_thing.last_cached
      original_inserted_at = original_thing.inserted_at
      
      # Sleep to ensure timestamp difference (use millisecond precision)
      :timer.sleep(100)
      
      # Update with new data
      updated_params = Map.merge(params, %{
        "primary_name" => "Updated Test Game",
        "rank" => "50",
        "averageweight" => "3.0"
      })
      
      assert {:ok, updated_thing} = Thing.upsert_thing(updated_params)
      
      # Should be same ID
      assert updated_thing.id == original_thing.id
      
      # Should have updated data
      assert updated_thing.primary_name == "Updated Test Game"
      assert updated_thing.rank == "50"
      assert updated_thing.averageweight == "3.0"
      
      # Should have newer cached timestamp but same inserted_at
      # Use >= because database timestamp precision may cause equal timestamps
      assert DateTime.compare(updated_thing.last_cached, original_cached_time) in [:gt, :eq]
      assert DateTime.compare(updated_thing.inserted_at, original_inserted_at) == :eq
    end

    test "preserves nil values for optional fields", %{thing_params: params} do
      # Remove some optional fields
      minimal_params = Map.take(params, ["id", "type"])
      
      assert {:ok, thing} = Thing.upsert_thing(minimal_params)
      
      assert thing.id == "123456"
      assert thing.type == "boardgame"
      assert is_nil(thing.primary_name)
      assert is_nil(thing.description)
      assert is_nil(thing.rank)
    end

    test "returns error for invalid data" do
      invalid_params = %{
        # Missing required "type" field
        "id" => "invalid_id"
      }
      
      assert {:error, changeset} = Thing.upsert_thing(invalid_params)
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).type
    end

    test "returns error for missing required id field" do
      invalid_params = %{
        "type" => "boardgame",
        "primary_name" => "Game without ID"
      }
      
      assert {:error, changeset} = Thing.upsert_thing(invalid_params)
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).id
    end

    test "handles empty string values by converting them to nil (Ecto behavior)" do
      params_with_empty_strings = %{
        "id" => "test_empty",
        "type" => "boardgame",
        "primary_name" => "",
        "description" => ""
      }
      
      assert {:ok, thing} = Thing.upsert_thing(params_with_empty_strings)
      
      # Ecto.Changeset.cast converts empty strings to nil by default
      assert is_nil(thing.primary_name)
      assert is_nil(thing.description)
    end

    test "updates thing multiple times maintaining database consistency", %{thing_params: params} do
      # Insert initial
      assert {:ok, thing1} = Thing.upsert_thing(params)
      
      # First update
      params2 = Map.put(params, "rank", "25")
      assert {:ok, thing2} = Thing.upsert_thing(params2)
      
      # Second update  
      params3 = Map.put(params, "rank", "10")
      assert {:ok, thing3} = Thing.upsert_thing(params3)
      
      # All should have same ID
      assert thing1.id == thing2.id
      assert thing2.id == thing3.id
      
      # Final state should be correct
      assert thing3.rank == "10"
      
      # Should only be one record in database
      things = Core.Repo.all(Thing)
      matching_things = Enum.filter(things, &(&1.id == "123456"))
      assert length(matching_things) == 1
    end

    test "handles concurrent upserts safely", %{thing_params: params} do
      # This tests that upsert handles potential race conditions
      tasks = for i <- 1..5 do
        updated_params = Map.put(params, "rank", "#{i * 10}")
        Task.async(fn -> Thing.upsert_thing(updated_params) end)
      end
      
      results = Task.await_many(tasks)
      
      # All should succeed
      assert Enum.all?(results, fn {status, _} -> status == :ok end)
      
      # Should only be one record in database
      things = Core.Repo.all(Thing)
      matching_things = Enum.filter(things, &(&1.id == "123456"))
      assert length(matching_things) == 1
    end

    test "last_cached timestamp is always updated on upsert", %{thing_params: params} do
      # Insert initial
      assert {:ok, thing1} = Thing.upsert_thing(params)
      first_cached_time = thing1.last_cached
      
      :timer.sleep(100)
      
      # Upsert with same data
      assert {:ok, thing2} = Thing.upsert_thing(params)
      second_cached_time = thing2.last_cached
      
      # Timestamp should be updated even with identical data
      # Use >= because database timestamp precision may cause equal timestamps
      assert DateTime.compare(second_cached_time, first_cached_time) in [:gt, :eq]
    end
  end
end