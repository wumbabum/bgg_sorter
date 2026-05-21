defmodule Web.CollectionLiveColumnSortTest do
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

  describe "column_sort preserves mechanics in URL" do
    test "clicking a sortable column while mechanics are selected keeps mechanics in the URL",
         %{conn: conn} do
      mechanic = setup_collection_with_shared_mechanic()

      {:ok, view, _html} =
        live(conn, "/collection/testuser?mechanics=#{mechanic.id}")

      Process.sleep(300)

      render_hook(view, "column_sort", %{"field" => "average"})

      path = assert_patch(view)
      assert path =~ "sort_by=average"
      assert path =~ "sort_direction=asc"
      assert path =~ "mechanics=#{mechanic.id}"
    end

    test "clicking a sortable column preserves filters, mechanics, and advanced_search together",
         %{conn: conn} do
      mechanic = setup_collection_with_shared_mechanic()

      {:ok, view, _html} =
        live(
          conn,
          "/collection/testuser?average=7&mechanics=#{mechanic.id}&advanced_search=true"
        )

      Process.sleep(300)

      render_hook(view, "column_sort", %{"field" => "average"})

      path = assert_patch(view)
      assert path =~ "sort_by=average"
      assert path =~ "average=7"
      assert path =~ "mechanics=#{mechanic.id}"
      assert path =~ "advanced_search=true"
    end
  end
end
