defmodule Web.Components.ModalComponent do
  @moduledoc "Modal component for displaying detailed board game information."

  use Phoenix.Component
  import Phoenix.HTML

  def game_modal(assigns) do
    ~H"""
    <%= if @modal_open do %>
      <div class="modal-overlay" phx-click="close_modal">
        <div class="modal-content" phx-click="stop_propagation">
          <div class="modal-header">
            <h2><%= @selected_thing.primary_name || "Board Game Details" %></h2>
            <button class="modal-close" phx-click="close_modal" aria-label="Close">×</button>
          </div>
          
          <div class="modal-body">
            <%= if @modal_loading do %>
              <div class="loading-spinner">
                <div class="spinner"></div>
                <p>Loading game details...</p>
              </div>
            <% else %>
              <%= if @modal_error do %>
                <div class="error-state">
                  <p class="error-message"><%= @modal_error %></p>
                  <button phx-click="retry_modal" class="retry-button">Retry</button>
                </div>
              <% else %>
                <%= render_game_details(assigns) %>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  defp render_game_details(assigns) do
    ~H"""
    <div class="game-details">
      <div class="game-main-info">
        <div class="game-image">
          <%= if @thing_details.image || @thing_details.thumbnail do %>
            <img 
              src={@thing_details.image || @thing_details.thumbnail} 
              alt={@thing_details.primary_name}
              class="game-detail-image"
            />
          <% else %>
            <div class="image-placeholder">No Image Available</div>
          <% end %>
        </div>
        
        <div class="game-info">
          <div class="game-title">
            <h3><%= @thing_details.primary_name %></h3>
            <%= if @thing_details.yearpublished do %>
              <span class="game-year">(<%= @thing_details.yearpublished %>)</span>
            <% end %>
          </div>
          
          <div class="game-stats">
            <div class="stat-row">
              <span class="stat-label">Players:</span>
              <span class="stat-value"><%= format_players(@thing_details) %></span>
            </div>
            
            <%= if @thing_details.playingtime do %>
              <div class="stat-row">
                <span class="stat-label">Playing Time:</span>
                <span class="stat-value"><%= format_playtime(@thing_details) %></span>
              </div>
            <% end %>
            
            <%= if @thing_details.minage do %>
              <div class="stat-row">
                <span class="stat-label">Minimum Age:</span>
                <span class="stat-value"><%= @thing_details.minage %> years</span>
              </div>
            <% end %>
            
            <%= if @thing_details.average do %>
              <div class="stat-row">
                <span class="stat-label">Average Rating:</span>
                <span class="stat-value"><%= format_rating(@thing_details.average) %>/10</span>
              </div>
            <% end %>
            
            <%= if @thing_details.usersrated do %>
              <div class="stat-row">
                <span class="stat-label">Users Rated:</span>
                <span class="stat-value"><%= @thing_details.usersrated %></span>
              </div>
            <% end %>
            
            <%= if @thing_details.averageweight do %>
              <div class="stat-row">
                <span class="stat-label">Complexity:</span>
                <span class="stat-value"><%= format_weight(@thing_details.averageweight) %>/5</span>
              </div>
            <% end %>
            
            <%= if @thing_details.rank do %>
              <div class="stat-row">
                <span class="stat-label">BGG Rank:</span>
                <span class="stat-value">#<%= @thing_details.rank %></span>
              </div>
            <% end %>
            
            <%= if @thing_details.owned do %>
              <div class="stat-row">
                <span class="stat-label">Owned by:</span>
                <span class="stat-value"><%= @thing_details.owned %> users</span>
              </div>
            <% end %>
          </div>
        </div>
      </div>
      
      <%= if @thing_details.description do %>
        <div class="game-description">
          <h4>Description</h4>
          <div class="description-content">
            <%= raw(format_description(@thing_details.description)) %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_players(thing) do
    cond do
      thing.minplayers && thing.maxplayers && thing.minplayers == thing.maxplayers ->
        "#{thing.minplayers}"
      
      thing.minplayers && thing.maxplayers ->
        "#{thing.minplayers}-#{thing.maxplayers}"
      
      thing.minplayers ->
        "#{thing.minplayers}+"
      
      true ->
        "N/A"
    end
  end

  defp format_playtime(thing) do
    cond do
      thing.minplaytime && thing.maxplaytime && thing.minplaytime != thing.maxplaytime ->
        "#{thing.minplaytime}-#{thing.maxplaytime} minutes"
      
      thing.playingtime ->
        "#{thing.playingtime} minutes"
        
      thing.minplaytime ->
        "#{thing.minplaytime} minutes"
        
      true ->
        "N/A"
    end
  end

  defp format_rating(rating) when is_binary(rating) do
    case Float.parse(rating) do
      {value, _} -> Float.round(value, 2)
      :error -> "N/A"
    end
  end
  
  defp format_rating(_), do: "N/A"

  defp format_weight(weight) when is_binary(weight) do
    case Float.parse(weight) do
      {value, _} -> Float.round(value, 2)
      :error -> "N/A"
    end
  end
  
  defp format_weight(_), do: "N/A"

  defp format_description(description) when is_binary(description) do
    # Basic HTML cleanup - replace common HTML entities and line breaks
    description
    |> String.replace("&nbsp;", " ")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("\n", "<br/>")
    |> String.replace("\r", "")
  end
  
  defp format_description(_), do: ""
end