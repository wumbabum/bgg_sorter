defmodule Web.Components.SearchComponent do
  @moduledoc "Search component for the main page search form."

  use Phoenix.Component

  def main_search(assigns) do
    ~H"""
    <div class="section-container">
      <div class="collection-header">
        <h1 class="collection-title">Board Game Collection Browser</h1>
        <div class="collection-subtitle">Enter a BoardGameGeek username to view their collection</div>
      </div>
    </div>

    <div style="text-align: center; margin-top: 40px; padding-bottom: 40px;">
      <form phx-submit="search_collection">
        <input
          type="text"
          name="username"
          placeholder="Enter BGG username..."
          class="search-input"
          style="font-size: 18px; padding: 12px; width: 300px; margin-right: 10px;"
        />
        <button type="submit" class="search-button" style="font-size: 18px; padding: 12px 20px;">
          Search Collection
        </button>
      </form>
    </div>
    """
  end
end
