defmodule Web.CollectionLiveAdvancedFiltersTest do
  use Web.ConnCase

  import Mox
  import Phoenix.LiveViewTest

  alias Core.Schemas.Thing

  @moduletag :capture_log

  setup :verify_on_exit!

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

  defp insert_cached_thing(id, name, average) do
    {:ok, thing} =
      Thing.upsert_thing(%{
        "id" => id,
        "type" => "boardgame",
        "primary_name" => name,
        "yearpublished" => "2024",
        "minplayers" => "2",
        "maxplayers" => "4",
        "average" => average
      })

    thing
  end

  defp setup_mixed_rating_collection do
    # 3 games: low, medium, high rating
    insert_cached_thing("low", "Low Rated Game", "5.0")
    insert_cached_thing("med", "Medium Rated Game", "7.0")
    insert_cached_thing("high", "Highly Rated Game", "9.0")

    items = [
      %{id: "low", name: "Low Rated Game"},
      %{id: "med", name: "Medium Rated Game"},
      %{id: "high", name: "Highly Rated Game"}
    ]

    Core.MockReqClient
    |> expect(:get, fn _url, _params, _headers ->
      {:ok, %Req.Response{status: 200, body: mock_collection_xml(items)}}
    end)

    :ok
  end

  describe "average (minimum rating) filter applies to cached data" do
    test "minimum rating filter excludes lower-rated games", %{conn: conn} do
      setup_mixed_rating_collection()

      {:ok, view, _html} = live(conn, "/collection/testuser?average=7")

      Process.sleep(300)
      html = render(view)

      # Should include medium (7.0) and high (9.0), exclude low (5.0)
      assert html =~ "Medium Rated Game"
      assert html =~ "Highly Rated Game"
      refute html =~ "Low Rated Game"
    end

    test "minimum rating filter works alongside sort", %{conn: conn} do
      setup_mixed_rating_collection()

      {:ok, view, _html} =
        live(conn, "/collection/testuser?average=7&sort_by=average&sort_direction=desc")

      Process.sleep(300)
      html = render(view)

      # Highly Rated Game should appear before Medium Rated Game
      assert html =~ "Highly Rated Game"
      assert html =~ "Medium Rated Game"
      refute html =~ "Low Rated Game"

      # Order check: highly comes before medium
      pos_high = :binary.match(html, "Highly Rated Game") |> elem(0)
      pos_med = :binary.match(html, "Medium Rated Game") |> elem(0)
      assert pos_high < pos_med
    end
  end
end
