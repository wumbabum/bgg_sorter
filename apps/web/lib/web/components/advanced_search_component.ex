defmodule Web.Components.AdvancedSearchComponent do
  @moduledoc "Advanced search component for filtering board game collections."

  use Phoenix.Component
  alias Web.Components.AdvancedSearchInputComponent
  alias Web.Components.MechanicsSearchComponent

  def advanced_search_form(assigns) do
    ~H"""
    <div class="section-container">
      <div class="search-header">
        <div class="search-header-content">
          <div class="search-title-section">
            <h1 class="collection-title">Advanced Collection Search</h1>
            <div class="collection-subtitle">Filter and search through BoardGameGeek collections</div>
          </div>
          <button
            type="button"
            phx-click="toggle_advanced_search"
            class="close-button"
            title="Close Advanced Search"
          >
            ×
          </button>
        </div>
      </div>
      <form phx-submit="advanced_search" class="advanced-search-form">
        <table class="advanced-search-table">
          <tbody>
            <!-- Username Field -->
            <AdvancedSearchInputComponent.text_input
              id="search-username"
              name="username"
              label="BGG Username"
              value={@username || ""}
              placeholder="Enter username to search their collection"
              size="35"
            />
            
    <!-- Board Game Name -->
            <AdvancedSearchInputComponent.text_input
              id="search-name"
              name="primary_name"
              label="Board Game Name"
              value={@filters[:primary_name] || ""}
              placeholder="Search by game name"
              size="35"
            />
            
    <!-- Number of Players -->
            <AdvancedSearchInputComponent.player_select selected_players={@filters[:players] || ""} />
            
    <!-- Playing Time -->
            <AdvancedSearchInputComponent.number_input
              id="search-playtime"
              name="playingtime"
              label="Playing Time (minutes)"
              value={@filters[:playingtime] || ""}
              placeholder="Time in minutes"
              suffix="minutes"
            />
            
    <!-- User Rating (Minimum) -->
            <AdvancedSearchInputComponent.number_input
              id="search-rating"
              name="average"
              label="Minimum User Rating"
              value={@filters[:average] || ""}
              placeholder="Rating (1-10)"
              suffix="or higher"
            />
            
    <!-- Maximum BGG Rank -->
            <AdvancedSearchInputComponent.number_input
              id="search-rank"
              name="rank"
              label="Maximum BGG Rank"
              value={@filters[:rank] || ""}
              placeholder="Rank number"
              suffix="or better (lower number)"
            />
            
    <!-- Weight Range (1-5) -->
            <AdvancedSearchInputComponent.range_input
              id="search-weight"
              name="averageweight"
              label="Weight (1-5)"
              min_value={@filters[:averageweight_min] || ""}
              max_value={@filters[:averageweight_max] || ""}
              suffix="(1 Light - 5 Heavy)"
            />
            
    <!-- Game Description -->
            <AdvancedSearchInputComponent.text_input
              id="search-description"
              name="description"
              label="Description Contains"
              value={@filters[:description] || ""}
              placeholder="Search within game descriptions"
              size="35"
            />
            
            <!-- Mechanics Filter -->
            <MechanicsSearchComponent.mechanics_filter_input
              selected_mechanics={Map.get(assigns, :selected_mechanics, MapSet.new())}
              all_mechanics_expanded={Map.get(assigns, :all_mechanics_expanded, false)}
              popular_mechanics={Map.get(assigns, :popular_mechanics, [])}
              mechanics_search_query={Map.get(assigns, :mechanics_search_query, "")}
              mechanics_search_results={Map.get(assigns, :mechanics_search_results, [])}
            />
          </tbody>
        </table>

        <div class="advanced-search-buttons">
          <button type="submit" class="advanced-search-submit">
            Search Collection
          </button>
          <button type="button" phx-click="clear_filters" class="clear-button">
            Clear All Filters
          </button>
        </div>
      </form>
    </div>
    """
  end
end
