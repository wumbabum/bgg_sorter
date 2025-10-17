defmodule Web.Components.HeaderComponent do
  @moduledoc "Header component with BGG logo and navigation."

  use Phoenix.Component

  def header(assigns) do
    # Set default values for optional assigns
    assigns = assign_new(assigns, :advanced_search, fn -> false end)

    ~H"""
    <div class="global-header" phx-hook="MobileSearchHook" id="global-header">
      <div class="global-header-content">
        <.link navigate="/" class="bgg-logo">
          <div class="bgg-icon">BGG</div>
          <span class="bgg-logo-text-full">Bgg Sorter</span>
          <span class="bgg-logo-text-mobile">Sorter</span>
        </.link>
        <div class="global-header-nav">
          <button
            phx-click="toggle_advanced_search"
            class={[
              "nav-link nav-button",
              @advanced_search && "active"
            ]}
          >
            <span class="advanced-full">Advanced Search</span>
            <span class="advanced-short">Advanced</span>
          </button>
          <div class="global-header-nav-search">
            <form phx-submit="search_collection" class="search-form">
              <input
                type="text"
                name="username"
                placeholder="Enter BGG username..."
                class="search-input"
                value={assigns[:username] || ""}
                autocomplete="on"
                autocapitalize="none"
                autocorrect="off"
                spellcheck="false"
              />
              <button
                type="submit"
                class="search-button"
                aria-label="Search"
                onclick="handleMobileSearch(event, this)"
              >
                <span class="search-text">Search</span>
                <span class="search-icon">🔍</span>
              </button>
            </form>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
