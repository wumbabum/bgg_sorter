defmodule Web.CollectionLiveHandleParamsTest do
  use Web.ConnCase

  import Mox
  import Phoenix.LiveViewTest

  alias Core.Repo
  alias Core.Schemas.Mechanic
  alias Core.Schemas.Thing
  alias Core.Schemas.ThingMechanic

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

  defp insert_mechanic(name) do
    {:ok, mechanic} =
      %Mechanic{}
      |> Mechanic.changeset(%{name: name, slug: Mechanic.generate_slug(name)})
      |> Repo.insert()

    mechanic
  end

  defp link_mechanic(thing_id, mechanic_id) do
    {:ok, _} =
      %ThingMechanic{}
      |> ThingMechanic.changeset(%{thing_id: thing_id, mechanic_id: mechanic_id})
      |> Repo.insert()

    :ok
  end

  defp setup_collection_with_shared_mechanic do
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

    mechanic = insert_mechanic("Worker Placement")
    link_mechanic("low", mechanic.id)
    link_mechanic("med", mechanic.id)
    link_mechanic("high", mechanic.id)
    mechanic
  end

  describe "handle_params honors multi-dimension URL changes" do
    test "URL change with both new filter AND new sort applies both", %{conn: conn} do
      setup_collection_with_shared_mechanic()

      # Start with no filters / default sort.
      {:ok, view, _html} = live(conn, "/collection/testuser")
      Process.sleep(300)

      # Patch the URL to change BOTH filters and sort simultaneously.
      # Previously the cond fall-through only honored the filters branch
      # and silently dropped the sort update.
      render_patch(
        view,
        "/collection/testuser?average=7&sort_by=average&sort_direction=desc"
      )

      Process.sleep(100)
      html = render(view)

      # Filter applied: low excluded
      assert html =~ "Medium Rated Game"
      assert html =~ "Highly Rated Game"
      refute html =~ "Low Rated Game"

      # Sort applied: high comes before med (descending by average)
      pos_high = :binary.match(html, "Highly Rated Game") |> elem(0)
      pos_med = :binary.match(html, "Medium Rated Game") |> elem(0)
      assert pos_high < pos_med
    end

    test "URL change with both new mechanics AND new sort applies both", %{conn: conn} do
      mechanic = setup_collection_with_shared_mechanic()

      {:ok, view, _html} = live(conn, "/collection/testuser")
      Process.sleep(300)

      # Patch the URL to change BOTH mechanics and sort simultaneously.
      # Previously the mechanics branch fired and dropped the sort change.
      render_patch(
        view,
        "/collection/testuser?mechanics=#{mechanic.id}&sort_by=average&sort_direction=desc"
      )

      Process.sleep(100)
      html = render(view)

      # All three games are linked to the mechanic so they should all be
      # visible, but ordered by average descending.
      assert html =~ "Highly Rated Game"
      assert html =~ "Medium Rated Game"
      assert html =~ "Low Rated Game"

      pos_high = :binary.match(html, "Highly Rated Game") |> elem(0)
      pos_med = :binary.match(html, "Medium Rated Game") |> elem(0)
      pos_low = :binary.match(html, "Low Rated Game") |> elem(0)
      assert pos_high < pos_med
      assert pos_med < pos_low
    end

    test "URL change with new filter AND new mechanics applies both", %{conn: conn} do
      mechanic = setup_collection_with_shared_mechanic()

      {:ok, view, _html} = live(conn, "/collection/testuser")
      Process.sleep(300)

      # Patch URL changing filters and mechanics together. Previously the
      # filters branch ran with stale (empty) socket selected_mechanics and
      # the mechanics URL value was silently dropped.
      render_patch(
        view,
        "/collection/testuser?average=7&mechanics=#{mechanic.id}"
      )

      Process.sleep(100)
      html = render(view)

      # Both filter and mechanic constraints applied: low excluded by average;
      # med and high included (both linked to the mechanic AND >= 7.0).
      assert html =~ "Medium Rated Game"
      assert html =~ "Highly Rated Game"
      refute html =~ "Low Rated Game"
    end
  end
end
