defmodule Web.CollectionLivePaginationTest do
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

  # Build a collection of 25 items so pagination kicks in (page size is 20).
  defp setup_25_item_collection do
    items =
      for i <- 1..25 do
        avg = Float.to_string(9.0 - i * 0.1)
        insert_cached_thing("g#{i}", "Game #{i}", avg)
        %{id: "g#{i}", name: "Game #{i}"}
      end

    Core.MockReqClient
    |> expect(:get, fn _url, _params, _headers ->
      {:ok, %Req.Response{status: 200, body: mock_collection_xml(items)}}
    end)

    :ok
  end

  describe "pagination preserves URL parameters" do
    test "next_page button preserves sort parameters in URL", %{conn: conn} do
      setup_25_item_collection()

      # Load page 1 with sort by rating descending
      {:ok, view, _html} =
        live(conn, "/collection/testuser?sort_by=average&sort_direction=desc")

      Process.sleep(300)

      # Click next page
      view |> element("button", "Next →") |> render_click()

      # The URL should preserve sort_by and sort_direction
      assert_patched(view, "/collection/testuser?page=2&sort_by=average&sort_direction=desc")
    end

    test "prev_page button preserves sort parameters in URL", %{conn: conn} do
      setup_25_item_collection()

      # Load page 2 with sort
      {:ok, view, _html} =
        live(
          conn,
          "/collection/testuser?page=2&sort_by=average&sort_direction=desc"
        )

      Process.sleep(300)

      view |> element("button", "← Previous") |> render_click()

      # When going back to page 1, sort should still be preserved
      path = assert_patch(view)
      assert path =~ "sort_by=average"
      assert path =~ "sort_direction=desc"
    end

    test "page navigator links preserve sort parameters", %{conn: conn} do
      setup_25_item_collection()

      {:ok, view, _html} =
        live(conn, "/collection/testuser?sort_by=average&sort_direction=desc")

      Process.sleep(300)
      html = render(view)

      # The page navigator's "Next »" link href should include sort params
      assert html =~ ~r/href="[^"]*sort_by=average[^"]*"/
      assert html =~ ~r/href="[^"]*sort_direction=desc[^"]*"/
    end

    test "page navigator links preserve filters", %{conn: conn} do
      setup_25_item_collection()

      # Load with a primary_name filter and sort
      {:ok, view, _html} =
        live(
          conn,
          "/collection/testuser?primary_name=Game&sort_by=average&sort_direction=desc"
        )

      Process.sleep(300)
      html = render(view)

      # Page navigator links should include the filter
      assert html =~ ~r/href="[^"]*primary_name=Game[^"]*"/
    end
  end

  describe "immediate_filter updates URL" do
    test "typing in primary_name text filter updates URL and preserves sort", %{conn: conn} do
      setup_25_item_collection()

      {:ok, view, _html} =
        live(conn, "/collection/testuser?sort_by=average&sort_direction=desc")

      Process.sleep(300)

      # Simulate typing in the primary_name filter input
      render_hook(view, "immediate_filter", %{"field" => "primary_name", "value" => "Game"})

      path = assert_patch(view)
      assert path =~ "primary_name=Game"
      assert path =~ "sort_by=average"
      assert path =~ "sort_direction=desc"
    end

    test "clearing a text filter removes it from URL", %{conn: conn} do
      setup_25_item_collection()

      {:ok, view, _html} =
        live(conn, "/collection/testuser?primary_name=Game&sort_by=average&sort_direction=desc")

      Process.sleep(300)

      # Clear the filter by sending an empty value
      render_hook(view, "immediate_filter", %{"field" => "primary_name", "value" => ""})

      path = assert_patch(view)
      refute path =~ "primary_name="
      # Sort should still be preserved
      assert path =~ "sort_by=average"
    end
  end
end
