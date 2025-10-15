defmodule Web.Components.MechanicsSearchComponent do
  @moduledoc "Component for mechanics filtering in advanced search."

  use Phoenix.Component
  alias Web.Components.MechanicsTagComponent

  @doc """
  Renders mechanics filter input with expandable "All" toggle and popular mechanics search.
  """
  attr :selected_mechanics, MapSet, default: MapSet.new(), doc: "Set of selected mechanic IDs"

  attr :all_mechanics_expanded, :boolean,
    default: false,
    doc: "Whether mechanics list is expanded"

  attr :popular_mechanics, :list, default: [], doc: "List of popular mechanics"

  attr :mechanics_loading, :boolean,
    default: false,
    doc: "Whether mechanics are currently loading"

  attr :mechanics_search_query, :string, default: "", doc: "Current search query"
  attr :mechanics_search_results, :list, default: [], doc: "Search results"

  def mechanics_filter_input(assigns) do
    ~H"""
    <tr>
      <td>Mechanics</td>
      <td>
        <div class="mechanics-filter-container">
          <!-- All Tag - Click to expand/collapse -->
          <div class="mechanics-all-section">
            <span
              class={"mechanic-tag mechanic-tag--all " <> if(@all_mechanics_expanded, do: "mechanic-tag--toggled", else: "")}
              phx-click="toggle_mechanic"
              phx-value-mechanic_id="all"
              tabindex="0"
            >
              <%= if @all_mechanics_expanded do %>
                <span class="arrow arrow--down">▼</span> All
              <% else %>
                <span class="arrow arrow--right">▶</span> All
              <% end %>
            </span>
          </div>
          
    <!-- Expandable Mechanics List (initially hidden) -->
          <%= if @all_mechanics_expanded do %>
            <div class="mechanics-expanded-section">
              <div class="mechanics-search-box">
                <input
                  type="text"
                  placeholder="Search mechanics..."
                  class="mechanics-search-input"
                  value={@mechanics_search_query}
                  phx-keyup="search_mechanics"
                  phx-debounce="300"
                />
              </div>
              <div class="mechanics-popular-list">
                <%= if @mechanics_search_query != "" do %>
                  <!-- Show search results -->
                  <%= if Enum.empty?(@mechanics_search_results) do %>
                    <p class="mechanics-loading">
                      No mechanics found matching "#{@mechanics_search_query}"
                    </p>
                  <% else %>
                    <%= for mechanic <- @mechanics_search_results do %>
                      <MechanicsTagComponent.mechanic_tag
                        mechanic={mechanic}
                        highlighted={MapSet.member?(@selected_mechanics, mechanic.id)}
                        clickable={true}
                        size={:small}
                      />
                    <% end %>
                  <% end %>
                <% else %>
                  <!-- Show popular mechanics -->
                  <%= cond do %>
                    <% @mechanics_loading -> %>
                      <p class="mechanics-loading">Loading popular mechanics...</p>
                    <% Enum.empty?(@popular_mechanics) -> %>
                      <p class="mechanics-loading">
                        No mechanics available yet. Mechanics are populated when games are loaded from BoardGameGeek.
                      </p>
                    <% true -> %>
                      <%= for mechanic <- @popular_mechanics do %>
                        <MechanicsTagComponent.mechanic_tag
                          mechanic={mechanic}
                          highlighted={MapSet.member?(@selected_mechanics, mechanic.id)}
                          clickable={true}
                          size={:small}
                        />
                      <% end %>
                  <% end %>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </td>
    </tr>
    """
  end
end
