defmodule Web.CollectionLiveTest do
  use Web.ConnCase

  import Phoenix.LiveViewTest

  describe "collection live view" do
    test "loads home page successfully", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/collection")

      # Verify home page loads without errors
      assert html =~ "Board Game Collection Browser"
    end

    test "loads advanced search page successfully", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/collection?advanced_search=true")

      # Verify advanced search form is displayed
      assert html =~ "Advanced Search"
      assert html =~ "Board Game Name"
    end

    test "handles URL with filter parameters without crashing", %{conn: conn} do
      # Test that URL filter parameters don't cause crashes (regression test)
      {:ok, _view, html} =
        live(conn, "/collection?players=2&primary_name=Wingspan&advanced_search=true")

      # Verify page loads and shows advanced search
      assert html =~ "Advanced Search"
    end
  end
end
