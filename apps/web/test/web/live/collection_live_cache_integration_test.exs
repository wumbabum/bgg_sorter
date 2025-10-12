defmodule Web.CollectionLiveCacheIntegrationTest do
  use Web.ConnCase, async: false
  import Phoenix.LiveViewTest
  
  alias Core.Schemas.Thing
  alias Core.BggCacher
  
  @moduletag :capture_log
  @moduletag :integration
  
  setup do
    # Clean up any existing cache data
    Core.Repo.delete_all(Thing)
    :ok
  end
  
  describe "cache integration with CollectionLive" do
    test "loads collection with cache integration", %{conn: conn} do
      # Mock basic collection response
      collection_response = %Core.Schemas.CollectionResponse{
        items: [
          %Thing{
            id: "68448",
            type: "boardgame",
            subtype: "boardgame", 
            primary_name: "7 Wonders",
            yearpublished: 2010
          },
          %Thing{
            id: "169786",
            type: "boardgame",
            subtype: "boardgame",
            primary_name: "Scythe", 
            yearpublished: 2016
          }
        ]
      }
      
      # Mock detailed things response
      detailed_things = [
        %Thing{
          id: "68448",
          type: "boardgame",
          subtype: "boardgame",
          primary_name: "7 Wonders",
          yearpublished: 2010,
          minplayers: 2,
          maxplayers: 7,
          playingtime: 30,
          minage: 10,
          average: 7.7,
          averageweight: 2.33,
          description: "You are the leader of one of the 7 great cities of the Ancient World."
        },
        %Thing{
          id: "169786", 
          type: "boardgame",
          subtype: "boardgame",
          primary_name: "Scythe",
          yearpublished: 2016,
          minplayers: 1,
          maxplayers: 5,
          playingtime: 90,
          minage: 14,
          average: 8.3,
          averageweight: 3.42,
          description: "It is a time of unrest in 1920s Europa."
        }
      ]
      
      # Set up mocks for BGG API calls
      Core.MockReqClient
      |> Mox.stub(:get, fn _url, _params, _headers ->
        case _url do
          url when String.contains?(url, "collection") ->
            # Collection API call
            {:ok, %Req.Response{
              status: 200,
              body: build_collection_xml(collection_response.items)
            }}
          url when String.contains?(url, "thing") ->
            # Things API call for detailed data
            {:ok, %Req.Response{
              status: 200,
              body: build_things_xml(detailed_things)
            }}
        end
      end)
      |> Mox.expect(:get, 2)  # Expect collection + things calls
      
      # Navigate to collection page
      {:ok, view, html} = live(conn, "/collection/testuser")
      
      # Wait for data to load
      assert render(view) =~ "7 Wonders"
      assert render(view) =~ "Scythe"
      
      # Verify cache was populated by checking database
      cached_things = Core.Repo.all(Thing)
      assert length(cached_things) == 2
      
      # Verify detailed data is in cache
      seven_wonders = Enum.find(cached_things, &(&1.id == "68448"))
      assert seven_wonders.average == 7.7
      assert seven_wonders.minplayers == 2
      assert seven_wonders.maxplayers == 7
      
      scythe = Enum.find(cached_things, &(&1.id == "169786"))
      assert scythe.average == 8.3
      assert scythe.minplayers == 1
      assert scythe.maxplayers == 5
    end
    
    test "uses cached data on subsequent loads", %{conn: conn} do
      # Pre-populate cache with fresh data
      cached_thing = %Thing{
        id: "68448",
        type: "boardgame", 
        subtype: "boardgame",
        primary_name: "7 Wonders",
        yearpublished: 2010,
        minplayers: 2,
        maxplayers: 7,
        average: 7.7,
        last_cached: DateTime.utc_now()
      }
      {:ok, _} = Thing.upsert_thing(cached_thing)
      
      # Mock only collection call - things call should not happen due to cache
      collection_response = %Core.Schemas.CollectionResponse{
        items: [cached_thing]
      }
      
      Core.MockReqClient
      |> Mox.stub(:get, fn _url, _params, _headers ->
        {:ok, %Req.Response{
          status: 200, 
          body: build_collection_xml(collection_response.items)
        }}
      end)
      |> Mox.expect(:get, 1)  # Only collection call expected
      
      # Navigate to collection page
      {:ok, view, html} = live(conn, "/collection/testuser")
      
      # Verify data loads from cache
      assert render(view) =~ "7 Wonders"
      
      # Verify no additional things were created (cache was used)
      cached_things = Core.Repo.all(Thing)
      assert length(cached_things) == 1
    end
    
    test "filters work with cached complete data", %{conn: conn} do
      # Set up collection with mixed player counts
      collection_response = %Core.Schemas.CollectionResponse{
        items: [
          %Thing{id: "1", primary_name: "Solo Game", minplayers: 1, maxplayers: 1},
          %Thing{id: "2", primary_name: "Two Player Game", minplayers: 2, maxplayers: 2},
          %Thing{id: "3", primary_name: "Party Game", minplayers: 4, maxplayers: 10}
        ]
      }
      
      detailed_things = collection_response.items
      
      Core.MockReqClient
      |> Mox.stub(:get, fn _url, _params, _headers ->
        case _url do
          url when String.contains?(url, "collection") ->
            {:ok, %Req.Response{
              status: 200,
              body: build_collection_xml(collection_response.items) 
            }}
          url when String.contains?(url, "thing") ->
            {:ok, %Req.Response{
              status: 200,
              body: build_things_xml(detailed_things)
            }}
        end
      end)
      |> Mox.expect(:get, 2)
      
      # Navigate with player filter
      {:ok, view, html} = live(conn, "/collection/testuser?players=2")
      
      # Should only show games that support 2 players
      rendered = render(view)
      refute rendered =~ "Solo Game"  # 1-1 players, doesn't support 2
      assert rendered =~ "Two Player Game"  # 2-2 players, supports 2
      refute rendered =~ "Party Game"  # 4-10 players, doesn't support 2
    end
    
    test "handles cache errors gracefully", %{conn: conn} do
      collection_response = %Core.Schemas.CollectionResponse{
        items: [%Thing{id: "1", primary_name: "Test Game"}]
      }
      
      # Mock collection success but things API failure
      Core.MockReqClient  
      |> Mox.stub(:get, fn _url, _params, _headers ->
        case _url do
          url when String.contains?(url, "collection") ->
            {:ok, %Req.Response{
              status: 200,
              body: build_collection_xml(collection_response.items)
            }}
          url when String.contains?(url, "thing") ->
            {:error, %RuntimeError{message: "API failure"}}
        end
      end)
      |> Mox.expect(:get, 2)
      
      # Navigate to collection page
      {:ok, view, html} = live(conn, "/collection/testuser")
      
      # Should show error message
      assert render(view) =~ "An unexpected error occurred"
    end
  end
  
  # Helper functions to build XML responses
  defp build_collection_xml(items) do
    items_xml = Enum.map(items, fn item ->
      ~s(<item objecttype="#{item.type}" objectid="#{item.id}" subtype="#{item.subtype}">
        <name sortindex="1">#{item.primary_name}</name>
        <yearpublished>#{item.yearpublished}</yearpublished>
      </item>)
    end) |> Enum.join("\n")
    
    ~s(<?xml version="1.0" encoding="utf-8" standalone="yes"?>
    <items totalitems="#{length(items)}">
      #{items_xml}
    </items>)
  end
  
  defp build_things_xml(items) do
    items_xml = Enum.map(items, fn item ->
      ~s(<item type="#{item.type}" id="#{item.id}">
        <name type="primary" sortindex="1" value="#{item.primary_name}" />
        <yearpublished value="#{item.yearpublished}" />
        <minplayers value="#{item.minplayers || 0}" />
        <maxplayers value="#{item.maxplayers || 0}" />
        <playingtime value="#{item.playingtime || 0}" />
        <minage value="#{item.minage || 0}" />
        <description>#{item.description || ""}</description>
        <statistics>
          <ratings>
            <average value="#{item.average || 0}" />
            <averageweight value="#{item.averageweight || 0}" />
          </ratings>
        </statistics>
      </item>)
    end) |> Enum.join("\n")
    
    ~s(<?xml version="1.0" encoding="utf-8" standalone="yes"?>
    <items>
      #{items_xml}  
    </items>)
  end
end