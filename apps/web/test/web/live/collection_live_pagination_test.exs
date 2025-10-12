defmodule Web.CollectionLivePaginationTest do
  use Web.ConnCase, async: false
  import Phoenix.LiveViewTest
  
  alias Core.Schemas.Thing
  
  @moduletag :capture_log
  
  setup do
    # Clean up any existing cache data
    Core.Repo.delete_all(Thing)
    :ok
  end
  
  describe "pagination without reloading" do
    test "navigating between pages uses existing filtered data", %{conn: conn} do
      # Create a large collection that will require multiple pages
      large_collection = for i <- 1..25 do
        %Thing{
          id: "#{i}",
          type: "boardgame",
          subtype: "boardgame",
          primary_name: "Game #{i}",
          yearpublished: 2000 + rem(i, 20),
          minplayers: rem(i, 4) + 1,
          maxplayers: rem(i, 4) + 3,
          average: 5.0 + (rem(i, 5) * 1.0),
          averageweight: 2.0 + (rem(i, 3) * 0.5)
        }
      end
      
      collection_response = %Core.Schemas.CollectionResponse{items: large_collection}
      
      # Mock BGG API - should only be called ONCE for initial load
      Core.MockReqClient
      |> Mox.expect(:get, 2, fn url, _params, _headers ->
        cond do
          String.contains?(url, "collection") ->
            {:ok, %Req.Response{
              status: 200,
              body: build_collection_xml(large_collection)
            }}
          String.contains?(url, "thing") ->
            {:ok, %Req.Response{
              status: 200, 
              body: build_things_xml(large_collection)
            }}
        end
      end)
      
      # Navigate to first page
      {:ok, view, _html} = live(conn, "/collection/testuser")
      
      # Verify we loaded the first page (items 1-20)
      assert render(view) =~ "Game 1"
      assert render(view) =~ "Game 20"
      refute render(view) =~ "Game 21"  # Should not show page 2 items
      
      # Navigate to second page - this should NOT trigger new API calls
      # because we set expect(:get, 2) above
      {:ok, view, _html} = live(conn, "/collection/testuser?page=2")
      
      # Verify we now see page 2 items (21-25)
      refute render(view) =~ "Game 1"   # Should not show page 1 items
      refute render(view) =~ "Game 20"  # Should not show page 1 items  
      assert render(view) =~ "Game 21"
      assert render(view) =~ "Game 25"
      
      # Navigate back to first page - again no new API calls
      {:ok, view, _html} = live(conn, "/collection/testuser?page=1") 
      
      # Verify we're back to page 1
      assert render(view) =~ "Game 1"
      assert render(view) =~ "Game 20"
      refute render(view) =~ "Game 21"
      
      # If we got here without Mox complaining about unexpected calls,
      # it means pagination used existing data without new API requests
    end
    
    test "changing filters does trigger reload", %{conn: conn} do
      # Small collection for this test
      collection = [
        %Thing{id: "1", primary_name: "Solo Game", minplayers: 1, maxplayers: 1},
        %Thing{id: "2", primary_name: "Two Player Game", minplayers: 2, maxplayers: 2}, 
        %Thing{id: "3", primary_name: "Party Game", minplayers: 4, maxplayers: 10}
      ]
      
      collection_response = %Core.Schemas.CollectionResponse{items: collection}
      
      # Mock will be called twice: once for initial load, once for filtered load
      Core.MockReqClient
      |> Mox.expect(:get, 4, fn url, _params, _headers ->
        cond do
          String.contains?(url, "collection") ->
            {:ok, %Req.Response{
              status: 200,
              body: build_collection_xml(collection)
            }}
          String.contains?(url, "thing") ->
            {:ok, %Req.Response{
              status: 200,
              body: build_things_xml(collection) 
            }}
        end
      end)
      
      # Navigate to collection
      {:ok, view, _html} = live(conn, "/collection/testuser")
      assert render(view) =~ "Solo Game"
      assert render(view) =~ "Party Game"
      
      # Navigate with filter - this SHOULD trigger new API calls
      {:ok, view, _html} = live(conn, "/collection/testuser?players=2")
      
      # Should only show games that support 2 players
      rendered = render(view)
      refute rendered =~ "Solo Game"    # 1-1 players
      assert rendered =~ "Two Player Game"  # 2-2 players
      refute rendered =~ "Party Game"   # 4-10 players
    end
  end
  
  # Helper functions
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
        <yearpublished value="#{item.yearpublished || 2000}" />
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