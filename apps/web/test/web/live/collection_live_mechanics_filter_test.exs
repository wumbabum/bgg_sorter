defmodule Web.CollectionLiveMechanicsFilterTest do
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

  defp setup_collection do
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

  defp setup_collection_with_shared_mechanic do
    setup_collection()
    mechanic = insert_mechanic("Worker Placement")
    link_mechanic("low", mechanic.id)
    link_mechanic("med", mechanic.id)
    link_mechanic("high", mechanic.id)
    mechanic
  end

  describe "changing mechanics preserves other active filters" do
    test "navigating to a URL that adds a mechanic keeps the average filter applied",
         %{conn: conn} do
      mechanic = setup_collection_with_shared_mechanic()

      # Start with average=7 only. The mechanic is linked to every game, so
      # adding it to the URL must NOT change which games are visible -- only
      # average >= 7 should remain in the rendered list.
      {:ok, view, _html} = live(conn, "/collection/testuser?average=7")

      Process.sleep(300)
      html = render(view)
      assert html =~ "Medium Rated Game"
      assert html =~ "Highly Rated Game"
      refute html =~ "Low Rated Game"

      # Now patch the URL to add the mechanic; this exercises the
      # `selected_mechanics != current_selected_mechanics` branch in
      # handle_params, which previously stripped the average filter.
      # render_patch updates the URL without remounting (no extra BGG call).
      render_patch(view, "/collection/testuser?average=7&mechanics=#{mechanic.id}")

      Process.sleep(100)
      html_after = render(view)
      assert html_after =~ "Medium Rated Game"
      assert html_after =~ "Highly Rated Game"
      refute html_after =~ "Low Rated Game"
    end

    test "toggling a mechanic via the UI keeps the average filter applied",
         %{conn: conn} do
      mechanic = setup_collection_with_shared_mechanic()

      {:ok, view, _html} = live(conn, "/collection/testuser?average=7")

      Process.sleep(300)
      html = render(view)
      assert html =~ "Medium Rated Game"
      assert html =~ "Highly Rated Game"
      refute html =~ "Low Rated Game"

      # Toggle the mechanic via the UI event handler. The legacy helper used
      # to wipe filter state from the rendered view; the rendered view should
      # still respect average >= 7.
      render_hook(view, "toggle_mechanic", %{"mechanic_id" => mechanic.id})

      html_after = render(view)
      assert html_after =~ "Medium Rated Game"
      assert html_after =~ "Highly Rated Game"
      refute html_after =~ "Low Rated Game"
    end

    test "toggling a mechanic off does not surface previously filtered items",
         %{conn: conn} do
      mechanic = setup_collection_with_shared_mechanic()

      # Start with both filters active.
      {:ok, view, _html} =
        live(conn, "/collection/testuser?average=7&mechanics=#{mechanic.id}")

      Process.sleep(300)
      html = render(view)
      assert html =~ "Medium Rated Game"
      assert html =~ "Highly Rated Game"
      refute html =~ "Low Rated Game"

      # Toggle the mechanic off. With the legacy mechanics-only helper this
      # would reveal Low Rated Game; now the average filter must survive.
      render_hook(view, "toggle_mechanic", %{"mechanic_id" => mechanic.id})

      html_after = render(view)
      assert html_after =~ "Medium Rated Game"
      assert html_after =~ "Highly Rated Game"
      refute html_after =~ "Low Rated Game"
    end
  end
end
