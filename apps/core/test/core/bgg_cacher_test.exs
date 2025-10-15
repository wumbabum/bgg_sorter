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

    test "returns IDs for things with nil schema_version" do
      # Create thing with nil schema_version
      thing_with_nil_schema = insert_thing_with_schema_version("nil_schema", nil)

      # Create thing with current schema version
      current_thing = insert_fresh_thing("current")

      thing_ids = [thing_with_nil_schema.id, current_thing.id]

      assert {:ok, stale_ids} = BggCacher.get_stale_thing_ids(thing_ids)
      assert stale_ids == ["nil_schema"]
    end

    test "returns IDs for things with outdated schema_version" do
      # Create thing with old schema version (1)
      old_schema_thing = insert_thing_with_schema_version("old_schema", 1)

      # Create thing with current schema version (2)
      current_thing = insert_fresh_thing("current")

      thing_ids = [old_schema_thing.id, current_thing.id]

      assert {:ok, stale_ids} = BggCacher.get_stale_thing_ids(thing_ids)
      assert stale_ids == ["old_schema"]
    end

    test "combines time-based and version-based staleness correctly" do
      # Fresh time but old schema version
      fresh_old_schema = insert_thing_with_schema_version("fresh_old", 1)

      # Stale time but current schema version
      stale_time = DateTime.add(DateTime.utc_now(), -(8 * 24 * 60 * 60), :second)
      stale_current_schema = insert_thing_with_cache("stale_current", stale_time)

      # Fresh time and current schema version
      fresh_current_schema = insert_fresh_thing("fresh_current")

      thing_ids = [fresh_old_schema.id, stale_current_schema.id, fresh_current_schema.id]

      assert {:ok, stale_ids} = BggCacher.get_stale_thing_ids(thing_ids)
      assert Enum.sort(stale_ids) == ["fresh_old", "stale_current"]
    end
  end

  # Note: get_all_cached_things is now private and tested through load_things_cache

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
      assert end_time - start_time >= 900
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

    test "applies database-level filtering" do
      # Create things with different characteristics for filtering tests
      {:ok, thing1} =
        Thing.upsert_thing(%{
          "id" => "wingspan",
          "type" => "boardgame",
          "primary_name" => "Wingspan",
          "average" => "8.1",
          "minplayers" => "1",
          "maxplayers" => "5",
          "averageweight" => "2.4"
        })

      {:ok, thing2} =
        Thing.upsert_thing(%{
          "id" => "azul",
          "type" => "boardgame",
          "primary_name" => "Azul",
          "average" => "7.8",
          "minplayers" => "2",
          "maxplayers" => "4",
          "averageweight" => "1.8"
        })

      input_things = [thing1, thing2]

      # Test rating filter: games with average rating >= 8.0
      rating_filters = %{average: "8.0"}
      assert {:ok, rating_filtered} = BggCacher.load_things_cache(input_things, rating_filters)
      assert length(rating_filtered) == 1
      assert hd(rating_filtered).primary_name == "Wingspan"

      # Test player count filter: 1-player games
      solo_filters = %{players: "1"}
      assert {:ok, solo_filtered} = BggCacher.load_things_cache(input_things, solo_filters)
      assert length(solo_filtered) == 1
      assert hd(solo_filtered).primary_name == "Wingspan"

      # Test player count filter: 2-player games (both support 2 players)
      two_player_filters = %{players: "2"}

      assert {:ok, two_player_filtered} =
               BggCacher.load_things_cache(input_things, two_player_filters)

      assert length(two_player_filtered) == 2

      # Test name filter
      name_filters = %{primary_name: "wing"}
      assert {:ok, name_filtered} = BggCacher.load_things_cache(input_things, name_filters)
      assert length(name_filtered) == 1
      assert hd(name_filtered).primary_name == "Wingspan"

      # Test weight filter with defaults
      # Should default max to 5
      weight_filters = %{averageweight_min: "2.0"}
      assert {:ok, weight_filtered} = BggCacher.load_things_cache(input_things, weight_filters)
      assert length(weight_filtered) == 1
      assert hd(weight_filtered).primary_name == "Wingspan"

      # Test empty filters returns all
      assert {:ok, all_items} = BggCacher.load_things_cache(input_things, %{})
      assert length(all_items) == 2
    end

    test "applies database-level sorting" do
      # Create things with different sortable characteristics
      {:ok, thing1} =
        Thing.upsert_thing(%{
          "id" => "azul",
          "type" => "boardgame",
          "primary_name" => "Azul",
          "average" => "7.8",
          "minplayers" => "2",
          "averageweight" => "1.8"
        })

      {:ok, thing2} =
        Thing.upsert_thing(%{
          "id" => "wingspan",
          "type" => "boardgame",
          "primary_name" => "Wingspan",
          "average" => "8.1",
          "minplayers" => "1",
          "averageweight" => "2.4"
        })

      {:ok, thing3} =
        Thing.upsert_thing(%{
          "id" => "gloomhaven",
          "type" => "boardgame",
          "primary_name" => "Gloomhaven",
          "average" => "8.7",
          "minplayers" => "1",
          "averageweight" => "3.9"
        })

      input_things = [thing1, thing2, thing3]

      # Test name sorting (ascending)
      assert {:ok, name_asc} = BggCacher.load_things_cache(input_things, %{}, :primary_name, :asc)
      name_order = Enum.map(name_asc, & &1.primary_name)
      assert name_order == ["Azul", "Gloomhaven", "Wingspan"]

      # Test name sorting (descending)
      assert {:ok, name_desc} =
               BggCacher.load_things_cache(input_things, %{}, :primary_name, :desc)

      name_desc_order = Enum.map(name_desc, & &1.primary_name)
      assert name_desc_order == ["Wingspan", "Gloomhaven", "Azul"]

      # Test rating sorting (descending - highest rated first)
      assert {:ok, rating_desc} = BggCacher.load_things_cache(input_things, %{}, :average, :desc)
      rating_order = Enum.map(rating_desc, & &1.primary_name)
      # 8.7, 8.1, 7.8
      assert rating_order == ["Gloomhaven", "Wingspan", "Azul"]

      # Test player count sorting (ascending - lowest player count first)
      assert {:ok, players_asc} = BggCacher.load_things_cache(input_things, %{}, :players, :asc)
      players_order = Enum.map(players_asc, & &1.primary_name)
      # Both Wingspan and Gloomhaven have minplayers=1, Azul has minplayers=2
      # Database should sort consistently within same player count
      assert Enum.take(players_order, 2) |> Enum.sort() == ["Gloomhaven", "Wingspan"]
      assert Enum.at(players_order, 2) == "Azul"

      # Test weight sorting (ascending - lightest first)
      assert {:ok, weight_asc} =
               BggCacher.load_things_cache(input_things, %{}, :averageweight, :asc)

      weight_order = Enum.map(weight_asc, & &1.primary_name)
      # 1.8, 2.4, 3.9
      assert weight_order == ["Azul", "Wingspan", "Gloomhaven"]
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

    test "refreshes things with outdated schema version" do
      # Create thing with old schema version (1)
      _old_schema_thing = insert_thing_with_schema_version("old_schema", 1)

      input_things = [%Thing{id: "old_schema", type: "boardgame"}]

      # Mock BGG API response for refresh
      mock_things = [build_thing("old_schema", "Updated Schema Game")]

      Core.MockReqClient
      |> expect(:get, fn _url, _params, _headers ->
        {:ok, %Req.Response{status: 200, body: mock_bgg_things_xml(mock_things)}}
      end)

      assert {:ok, cached_things} = BggCacher.load_things_cache(input_things)

      assert length(cached_things) == 1
      updated_thing = hd(cached_things)
      assert updated_thing.id == "old_schema"
      assert updated_thing.primary_name == "Updated Schema Game"
      # Should have updated schema version
      assert updated_thing.schema_version == 2
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

  defp insert_thing_with_schema_version(id, schema_version) do
    {:ok, thing} =
      %{
        "id" => id,
        "type" => "boardgame",
        "primary_name" => "Game #{id}"
      }
      |> Thing.upsert_thing()

    # Manually set the schema version
    thing |> Ecto.Changeset.change(schema_version: schema_version) |> Core.Repo.update!()
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
        mechanics_links = ""

        ~s(<item type="#{thing.type}" id="#{thing.id}">
            <name type="primary" sortindex="1" value="#{thing.primary_name}" />
            <yearpublished value="#{thing.yearpublished}" />
            <minplayers value="#{thing.minplayers}" />
            <maxplayers value="#{thing.maxplayers}" />
            <playingtime value="#{thing.playingtime}" />
            #{mechanics_links}
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
