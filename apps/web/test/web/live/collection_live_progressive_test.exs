defmodule Web.CollectionLiveProgressiveTest do
  use Web.ConnCase

  import Mox
  import Phoenix.LiveViewTest

  alias Core.Schemas.Thing

  @moduletag :capture_log

  setup :verify_on_exit!

  # Helper to build mock collection XML response
  defp mock_collection_xml(items) do
    item_xml =
      Enum.map(items, fn %{id: id, name: name} ->
        ~s(<item objecttype="thing" objectid="#{id}" subtype="boardgame">
            <name sortindex="1">#{name}</name>
            <yearpublished>2024</yearpublished>
          </item>)
      end)
      |> Enum.join("")

    ~s(<?xml version="1.0" encoding="utf-8"?>
       <items totalitems="#{length(items)}">#{item_xml}</items>)
  end

  # Helper to build mock things XML response
  defp mock_things_xml(things) do
    item_xml =
      Enum.map(things, fn %{id: id, name: name} ->
        ~s(<item type="boardgame" id="#{id}">
            <name type="primary" sortindex="1" value="#{name}" />
            <yearpublished value="2024" />
            <minplayers value="2" />
            <maxplayers value="4" />
            <playingtime value="60" />
            <statistics>
              <ratings>
                <average value="7.5" />
                <ranks>
                  <rank type="subtype" id="1" name="boardgame" value="500" />
                </ranks>
              </ratings>
            </statistics>
          </item>)
      end)
      |> Enum.join("")

    ~s(<?xml version="1.0" encoding="utf-8"?>
       <items totalitems="#{length(things)}">#{item_xml}</items>)
  end

  # Helper to insert a fresh cached thing into the DB
  defp insert_cached_thing(id, name) do
    {:ok, thing} =
      Thing.upsert_thing(%{
        "id" => id,
        "type" => "boardgame",
        "primary_name" => name,
        "yearpublished" => "2024",
        "minplayers" => "2",
        "maxplayers" => "4"
      })

    thing
  end

  describe "progressive loading — all items cached" do
    test "displays cached items immediately without BGG things API call", %{conn: conn} do
      # Pre-populate DB with cached things
      insert_cached_thing("100", "Cached Game A")
      insert_cached_thing("200", "Cached Game B")

      # Mock collection API (1 call) — returns the 2 game IDs
      Core.MockReqClient
      |> expect(:get, 1, fn _url, params, _headers ->
        # This should be the collection endpoint
        if String.contains?(to_string(params["username"] || params[:username] || ""), "") do
          {:ok, %Req.Response{status: 200, body: mock_collection_xml([
            %{id: "100", name: "Cached Game A"},
            %{id: "200", name: "Cached Game B"}
          ])}}
        end
      end)
      # No things API call expected — if it tries, Mox will fail

      {:ok, view, _html} = live(conn, "/collection/testuser")

      # Wait for async processing
      Process.sleep(200)
      html = render(view)

      # Should display both cached games
      assert html =~ "Cached Game A"
      assert html =~ "Cached Game B"

      # Should NOT show background loading indicator
      refute html =~ "Loading"
    end
  end

  describe "progressive loading — no items cached" do
    test "shows items after BGG things API responds", %{conn: conn} do
      # Mock collection API
      Core.MockReqClient
      |> expect(:get, 1, fn url, _params, _headers ->
        if String.contains?(url, "collection") do
          {:ok, %Req.Response{status: 200, body: mock_collection_xml([
            %{id: "300", name: "New Game"}
          ])}}
        end
      end)
      # Mock things API — fetches the uncached game
      |> expect(:get, 1, fn url, _params, _headers ->
        if String.contains?(url, "thing") do
          {:ok, %Req.Response{status: 200, body: mock_things_xml([
            %{id: "300", name: "New Game"}
          ])}}
        end
      end)

      {:ok, view, _html} = live(conn, "/collection/testuser")

      # Wait for async processing (collection API + things API + DB)
      Process.sleep(500)
      html = render(view)

      # Should display the game after chunk is processed
      assert html =~ "New Game"
    end
  end

  describe "progressive loading — mixed cached and stale" do
    test "displays cached items first, then adds stale items after API fetch", %{conn: conn} do
      # Pre-populate DB with one cached thing
      insert_cached_thing("400", "Already Cached")

      # Mock collection API — returns 2 games (1 cached, 1 new)
      Core.MockReqClient
      |> expect(:get, 1, fn url, _params, _headers ->
        if String.contains?(url, "collection") do
          {:ok, %Req.Response{status: 200, body: mock_collection_xml([
            %{id: "400", name: "Already Cached"},
            %{id: "500", name: "Not Yet Cached"}
          ])}}
        end
      end)
      # Mock things API — only called for the uncached game
      |> expect(:get, 1, fn url, _params, _headers ->
        if String.contains?(url, "thing") do
          {:ok, %Req.Response{status: 200, body: mock_things_xml([
            %{id: "500", name: "Not Yet Cached"}
          ])}}
        end
      end)

      {:ok, view, _html} = live(conn, "/collection/testuser")

      # Wait for async processing
      Process.sleep(500)
      html = render(view)

      # Both games should be displayed
      assert html =~ "Already Cached"
      assert html =~ "Not Yet Cached"
    end

    test "shows background loading indicator while stale items are being fetched", %{conn: conn} do
      # Pre-populate DB with one cached thing
      insert_cached_thing("600", "Cached One")

      # Mock collection API
      Core.MockReqClient
      |> expect(:get, 1, fn url, _params, _headers ->
        if String.contains?(url, "collection") do
          {:ok, %Req.Response{status: 200, body: mock_collection_xml([
            %{id: "600", name: "Cached One"},
            %{id: "700", name: "Uncached One"}
          ])}}
        end
      end)
      # Mock things API with a small delay to ensure we can catch the loading state
      |> expect(:get, 1, fn url, _params, _headers ->
        if String.contains?(url, "thing") do
          Process.sleep(100)
          {:ok, %Req.Response{status: 200, body: mock_things_xml([
            %{id: "700", name: "Uncached One"}
          ])}}
        end
      end)

      {:ok, view, _html} = live(conn, "/collection/testuser")

      # Brief wait — cached items should be displayed, background loading should be active
      Process.sleep(100)
      html = render(view)

      # Cached game should be visible
      assert html =~ "Cached One"
      # Background loading indicator should be present
      assert html =~ "Loading" or html =~ "loading"

      # Wait for everything to finish
      Process.sleep(600)
      html = render(view)

      # Both games visible, no more loading
      assert html =~ "Cached One"
      assert html =~ "Uncached One"
    end
  end
end
