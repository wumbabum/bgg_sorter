defmodule Web.CollectionLiveModalUrlTest do
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

  # Sets up a collection where every thing has the returned mechanic linked,
  # so URL `?mechanics=<id>` does not filter everything out.
  defp setup_collection_with_shared_mechanic do
    setup_collection()
    mechanic = insert_mechanic("Worker Placement")
    link_mechanic("low", mechanic.id)
    link_mechanic("med", mechanic.id)
    link_mechanic("high", mechanic.id)
    mechanic
  end

  describe "open_thing_modal preserves URL state" do
    test "opening a modal preserves sort parameters in URL", %{conn: conn} do
      setup_collection()

      {:ok, view, _html} =
        live(conn, "/collection/testuser?sort_by=average&sort_direction=desc")

      Process.sleep(300)

      # Trigger open_thing_modal for one of the games
      render_hook(view, "open_thing_modal", %{"thing_id" => "med"})

      path = assert_patch(view)
      assert path =~ "modal_thing_id=med"
      assert path =~ "sort_by=average"
      assert path =~ "sort_direction=desc"
    end

    test "opening a modal preserves selected mechanics in URL", %{conn: conn} do
      mechanic = setup_collection_with_shared_mechanic()

      {:ok, view, _html} =
        live(
          conn,
          "/collection/testuser?mechanics=#{mechanic.id}&sort_by=average&sort_direction=desc"
        )

      Process.sleep(300)

      render_hook(view, "open_thing_modal", %{"thing_id" => "med"})

      path = assert_patch(view)
      assert path =~ "modal_thing_id=med"
      assert path =~ "sort_by=average"
      assert path =~ "sort_direction=desc"
      assert path =~ "mechanics=#{mechanic.id}"
    end

    test "opening a modal preserves filters, sort, mechanics, and advanced_search", %{conn: conn} do
      mechanic = setup_collection_with_shared_mechanic()

      {:ok, view, _html} =
        live(
          conn,
          "/collection/testuser?average=7&mechanics=#{mechanic.id}&sort_by=average&sort_direction=desc&advanced_search=true"
        )

      Process.sleep(300)

      render_hook(view, "open_thing_modal", %{"thing_id" => "high"})

      path = assert_patch(view)
      assert path =~ "modal_thing_id=high"
      assert path =~ "average=7"
      assert path =~ "mechanics=#{mechanic.id}"
      assert path =~ "sort_by=average"
      assert path =~ "sort_direction=desc"
      assert path =~ "advanced_search=true"
    end
  end
end
