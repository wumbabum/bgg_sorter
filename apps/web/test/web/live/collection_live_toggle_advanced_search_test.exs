defmodule Web.CollectionLiveToggleAdvancedSearchTest do
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
    insert_cached_thing("g1", "Game One", "7.0")
    insert_cached_thing("g2", "Game Two", "8.0")

    items = [
      %{id: "g1", name: "Game One"},
      %{id: "g2", name: "Game Two"}
    ]

    Core.MockReqClient
    |> expect(:get, fn _url, _params, _headers ->
      {:ok, %Req.Response{status: 200, body: mock_collection_xml(items)}}
    end)

    mechanic = insert_mechanic("Worker Placement")
    link_mechanic("g1", mechanic.id)
    link_mechanic("g2", mechanic.id)
    mechanic
  end

  describe "toggle_advanced_search preserves mechanics in URL" do
    test "toggling the advanced search panel on keeps selected mechanics in the URL",
         %{conn: conn} do
      mechanic = setup_collection_with_shared_mechanic()

      {:ok, view, _html} =
        live(
          conn,
          "/collection/testuser?mechanics=#{mechanic.id}&sort_by=average&sort_direction=desc"
        )

      Process.sleep(300)

      render_hook(view, "toggle_advanced_search", %{})

      path = assert_patch(view)
      assert path =~ "advanced_search=true"
      assert path =~ "mechanics=#{mechanic.id}"
      assert path =~ "sort_by=average"
      assert path =~ "sort_direction=desc"
    end

    test "toggling the advanced search panel off keeps selected mechanics in the URL",
         %{conn: conn} do
      mechanic = setup_collection_with_shared_mechanic()

      {:ok, view, _html} =
        live(
          conn,
          "/collection/testuser?mechanics=#{mechanic.id}&sort_by=average&sort_direction=desc&advanced_search=true"
        )

      Process.sleep(300)

      render_hook(view, "toggle_advanced_search", %{})

      path = assert_patch(view)
      refute path =~ "advanced_search=true"
      assert path =~ "mechanics=#{mechanic.id}"
      assert path =~ "sort_by=average"
      assert path =~ "sort_direction=desc"
    end
  end
end
