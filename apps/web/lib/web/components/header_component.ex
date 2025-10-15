defmodule Web.Components.HeaderComponent do
  @moduledoc "Header component with BGG logo and navigation."

  use Phoenix.Component

  def header(assigns) do
    # Set default values for optional assigns
    assigns = assign_new(assigns, :advanced_search, fn -> false end)

    ~H"""
    <div class="global-header">
      <div class="global-header-content">
        <.link navigate="/" class="bgg-logo">
          <div class="bgg-icon">BGG</div>
          Bgg Sorter
        </.link>
        <div class="global-header-nav">
          <button
            phx-click="toggle_advanced_search"
            class={[
              "nav-link nav-button",
              @advanced_search && "active"
            ]}
          >
            Advanced Search
          </button>
          <div class="global-header-nav-search">
            <form phx-submit="search_collection">
              <input
                type="text"
                name="username"
                placeholder="Enter BGG username..."
                class="search-input"
                value={assigns[:username] || ""}
              />
              <button type="submit" class="search-button">Search</button>
            </form>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
