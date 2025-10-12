defmodule Core.BggCacherTest do
  use Core.DataCase, async: true
  
  import Mox
  
  alias Core.BggCacher
  alias Core.Schemas.Thing
  
  @moduletag :capture_log
  
  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  describe "get_stale_thing_ids/1" do
    test "returns empty list when no thing IDs provided" do
      assert {:ok, []} = BggCacher.get_stale_thing_ids([])
    end

    test "returns all IDs when things don't exist in database" do
      thing_ids = ["123", "456", "789"]
      
      assert {:ok, stale_ids} = BggCacher.get_stale_thing_ids(thing_ids)
      assert Enum.sort(stale_ids) == Enum.sort(thing_ids)
    end

    test "returns IDs for things with nil last_cached" do
      # Create things with nil last_cached (simulate never cached)
      thing1 = insert_thing_without_cache("123")
      thing2 = insert_thing_without_cache("456")
      fresh_thing = insert_fresh_thing("789")
      
      thing_ids = [thing1.id, thing2.id, fresh_thing.id]
      
      assert {:ok, stale_ids} = BggCacher.get_stale_thing_ids(thing_ids)
      assert Enum.sort(stale_ids) == ["123", "456"]
    end

    test "returns IDs for things with stale last_cached" do
      # Create thing with stale cache (older than 1 week)
      stale_time = DateTime.add(DateTime.utc_now(), -(8 * 24 * 60 * 60), :second)
      stale_thing = insert_thing_with_cache("123", stale_time)
      
      # Create fresh thing (within 1 week)
      fresh_thing = insert_fresh_thing("456")
      
      thing_ids = [stale_thing.id, fresh_thing.id]
      
      assert {:ok, stale_ids} = BggCacher.get_stale_thing_ids(thing_ids)
      assert stale_ids == ["123"]
    end

    test "combines stale, nil, and missing IDs correctly" do
      # Stale thing
      stale_time = DateTime.add(DateTime.utc_now(), -(8 * 24 * 60 * 60), :second)
      stale_thing = insert_thing_with_cache("stale", stale_time)
      
      # Never cached thing
      never_cached = insert_thing_without_cache("never")
      
      # Fresh thing
      fresh_thing = insert_fresh_thing("fresh")
      
      # Missing thing (not in database)
      thing_ids = [stale_thing.id, never_cached.id, fresh_thing.id, "missing"]
      
      assert {:ok, stale_ids} = BggCacher.get_stale_thing_ids(thing_ids)
      assert Enum.sort(stale_ids) == ["missing", "never", "stale"]
    end
  end

  describe "get_all_cached_things/1" do
    test "returns empty list for empty input" do
      assert {:ok, []} = BggCacher.get_all_cached_things([])
    end

    test "returns cached things for existing IDs" do
      _thing1 = insert_fresh_thing("123")
      _thing2 = insert_fresh_thing("456")
      
      assert {:ok, cached_things} = BggCacher.get_all_cached_things(["123", "456"])
      
      cached_ids = Enum.map(cached_things, & &1.id)
      assert Enum.sort(cached_ids) == ["123", "456"]
    end

    test "returns only existing things when some IDs are missing" do
      _thing1 = insert_fresh_thing("123")
      
      assert {:ok, cached_things} = BggCacher.get_all_cached_things(["123", "missing"])
      
      assert length(cached_things) == 1
      assert hd(cached_things).id == "123"
    end
  end

  describe "update_stale_things/1" do
    test "returns ok with empty list for no stale IDs" do
      assert {:ok, []} = BggCacher.update_stale_things([])
    end

    test "calls BGG API and upserts things for single chunk" do
      stale_ids = ["123", "456"]
      
      # Mock BGG API response
      mock_things = [
        build_thing("123", "Game 1"),
        build_thing("456", "Game 2")
      ]
      
      Core.MockReqClient
      |> expect(:get, fn _url, _params, _headers ->
        {:ok, %Req.Response{status: 200, body: mock_bgg_things_xml(mock_things)}}
      end)
      
      assert {:ok, updated_things} = BggCacher.update_stale_things(stale_ids)
      
      assert length(updated_things) == 2
      updated_ids = Enum.map(updated_things, & &1.id)
      assert Enum.sort(updated_ids) == ["123", "456"]
      
      # Verify things were persisted to database
      db_things = Core.Repo.all(Thing)
      assert length(db_things) == 2
    end

    test "handles multiple chunks with rate limiting" do
      # Create 25 IDs to trigger chunking (20 + 5)
      stale_ids = for i <- 1..25, do: "#{i}"
      
      # Mock first chunk (20 items)
      first_chunk_things = for i <- 1..20, do: build_thing("#{i}", "Game #{i}")
      # Mock second chunk (5 items)  
      second_chunk_things = for i <- 21..25, do: build_thing("#{i}", "Game #{i}")
      
      Core.MockReqClient
      |> expect(:get, 2, fn _url, params, _headers ->
        id_param = params[:id] || params["id"]
        ids = String.split(to_string(id_param), ",")
        
        cond do
          length(ids) == 20 ->
            {:ok, %Req.Response{status: 200, body: mock_bgg_things_xml(first_chunk_things)}}
          length(ids) == 5 ->
            {:ok, %Req.Response{status: 200, body: mock_bgg_things_xml(second_chunk_things)}}
        end
      end)
      
      # Capture start time for rate limiting test
      start_time = System.monotonic_time(:millisecond)
      
      assert {:ok, updated_things} = BggCacher.update_stale_things(stale_ids)
      
      end_time = System.monotonic_time(:millisecond)
      
      # Should have processed all things
      assert length(updated_things) == 25
      
      # Should have taken at least 1 second due to rate limiting
      # (allowing some tolerance for test execution time)
      assert (end_time - start_time) >= 900
    end

    test "continues processing on chunk failure" do
      # Use exactly 21 IDs to guarantee 2 chunks: 20 + 1
      stale_ids = for i <- 1..21, do: "item#{i}"
      
      # Mock successful first chunk (20 items)
      first_chunk_things = for i <- 1..20, do: build_thing("item#{i}", "Game #{i}")
      
      Core.MockReqClient
      |> expect(:get, 1, fn _url, _params, _headers ->
        {:ok, %Req.Response{status: 200, body: mock_bgg_things_xml(first_chunk_things)}}
      end)
      # Mock failed second chunk (1 item)
      |> expect(:get, 1, fn _url, _params, _headers ->
        {:error, %RuntimeError{message: "API failure"}}
      end)
      
      assert {:ok, updated_things} = BggCacher.update_stale_things(stale_ids)
      
      # Should only have things from successful chunk
      assert length(updated_things) == 20
      first_item = Enum.find(updated_things, &(&1.id == "item1"))
      assert first_item.primary_name == "Game 1"
    end
  end

  describe "load_things_cache/1" do
    test "returns cached things when all are fresh" do
      # Create fresh things in database
      _thing1 = insert_fresh_thing("123") 
      _thing2 = insert_fresh_thing("456")
      
      input_things = [
        %Thing{id: "123", type: "boardgame"},
        %Thing{id: "456", type: "boardgame"}
      ]
      
      assert {:ok, cached_things} = BggCacher.load_things_cache(input_things)
      
      assert length(cached_things) == 2
      cached_ids = Enum.map(cached_things, & &1.id)
      assert Enum.sort(cached_ids) == ["123", "456"]
      
      # Should have complete data from database
      first_thing = Enum.find(cached_things, &(&1.id == "123"))
      assert first_thing.primary_name == "Fresh Game 123"
    end

    test "fetches and caches stale things" do
      # Create stale thing in database
      stale_time = DateTime.add(DateTime.utc_now(), -(8 * 24 * 60 * 60), :second)
      _stale_thing = insert_thing_with_cache("stale", stale_time)
      
      input_things = [%Thing{id: "stale", type: "boardgame"}]
      
      # Mock BGG API response for refresh
      mock_things = [build_thing("stale", "Refreshed Game")]
      
      Core.MockReqClient
      |> expect(:get, fn _url, _params, _headers ->
        {:ok, %Req.Response{status: 200, body: mock_bgg_things_xml(mock_things)}}
      end)
      
      assert {:ok, cached_things} = BggCacher.load_things_cache(input_things)
      
      assert length(cached_things) == 1
      refreshed_thing = hd(cached_things)
      assert refreshed_thing.id == "stale"
      assert refreshed_thing.primary_name == "Refreshed Game"
      
      # Should have updated timestamp
      assert %DateTime{} = refreshed_thing.last_cached
    end

    test "handles mix of fresh and stale things" do
      # Fresh thing
      _fresh_thing = insert_fresh_thing("fresh")
      
      # Stale thing
      stale_time = DateTime.add(DateTime.utc_now(), -(8 * 24 * 60 * 60), :second)
      _stale_thing = insert_thing_with_cache("stale", stale_time)
      
      input_things = [
        %Thing{id: "fresh", type: "boardgame"},
        %Thing{id: "stale", type: "boardgame"}
      ]
      
      # Mock BGG API response only for stale thing
      mock_things = [build_thing("stale", "Refreshed Stale")]
      
      Core.MockReqClient
      |> expect(:get, fn _url, _params, _headers ->
        {:ok, %Req.Response{status: 200, body: mock_bgg_things_xml(mock_things)}}
      end)
      
      assert {:ok, cached_things} = BggCacher.load_things_cache(input_things)
      
      assert length(cached_things) == 2
      
      fresh_cached = Enum.find(cached_things, &(&1.id == "fresh"))
      stale_cached = Enum.find(cached_things, &(&1.id == "stale"))
      
      assert fresh_cached.primary_name == "Fresh Game fresh"
      assert stale_cached.primary_name == "Refreshed Stale"
    end
  end

  # Helper functions for testing
  defp insert_thing_without_cache(id) do
    {:ok, thing} = 
      %{
        "id" => id,
        "type" => "boardgame", 
        "primary_name" => "Game #{id}",
        "last_cached" => nil
      }
      |> Thing.upsert_thing()
    
    # Manually set last_cached to nil to simulate never cached
    thing |> Ecto.Changeset.change(last_cached: nil) |> Core.Repo.update!()
  end

  defp insert_thing_with_cache(id, cached_time) do
    {:ok, thing} = 
      %{
        "id" => id,
        "type" => "boardgame",
        "primary_name" => "Game #{id}"
      }
      |> Thing.upsert_thing()
    
    # Manually set the cached time (truncate microseconds for database compatibility)
    truncated_time = DateTime.truncate(cached_time, :second)
    thing |> Ecto.Changeset.change(last_cached: truncated_time) |> Core.Repo.update!()
  end

  defp insert_fresh_thing(id) do
    {:ok, thing} = 
      %{
        "id" => id,
        "type" => "boardgame",
        "primary_name" => "Fresh Game #{id}",
        "yearpublished" => "2023",
        "minplayers" => "2",
        "maxplayers" => "4"
      }
      |> Thing.upsert_thing()
    
    thing
  end

  defp build_thing(id, name) do
    %Thing{
      id: id,
      type: "boardgame",
      primary_name: name,
      yearpublished: "2024",
      minplayers: "1",
      maxplayers: "4",
      playingtime: "60",
      rank: "100"
    }
  end

  defp mock_bgg_things_xml(things) do
    items = 
      things
      |> Enum.map(fn thing ->
        ~s(<item type="#{thing.type}" id="#{thing.id}">
            <name type="primary" sortindex="1" value="#{thing.primary_name}" />
            <yearpublished value="#{thing.yearpublished}" />
            <minplayers value="#{thing.minplayers}" />
            <maxplayers value="#{thing.maxplayers}" />
            <playingtime value="#{thing.playingtime}" />
            <statistics>
              <ratings>
                <ranks>
                  <rank type="subtype" id="1" name="boardgame" friendlyname="Board Game Rank" value="#{thing.rank}" />
                </ranks>
              </ratings>
            </statistics>
          </item>)
      end)
      |> Enum.join("")
    
    ~s(<?xml version="1.0" encoding="utf-8"?>
       <items totalitems="#{length(things)}">
         #{items}
       </items>)
  end
end