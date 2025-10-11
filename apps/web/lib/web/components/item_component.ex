defmodule Web.Components.ItemComponent do
  @moduledoc "Item component for displaying board game collections in table rows."

  use Phoenix.Component

  def item_row(assigns) do
    ~H"""
    <tr class="collection-row" phx-click="open_thing_modal" phx-value-thing_id={@item.id}>
      <td class="collection_thumbnail">
        <%= if @item.image || @item.thumbnail do %>
          <img 
            src={@item.image || @item.thumbnail} 
            alt={@item.primary_name} 
          />
        <% else %>
          <div class="item-placeholder">No Image</div>
        <% end %>
      </td>
      
      <td class="collection_objectname">
        <div>
          <a href="#" class="primary"><%= @item.primary_name %></a>
          <%= if @item.yearpublished do %>
            <span class="year">(<%= @item.yearpublished %>)</span>
          <% end %>
        </div>
        <%= if @item.description do %>
          <div class="description">
            <%= truncate_description(@item.description) %>
          </div>
        <% end %>
      </td>
      
      <td class="collection_players">
        <%= format_players(@item) %>
      </td>
      
      <td class="collection_rating">
        <%= format_rating(@item.average) %>
      </td>
      
      <td class="collection_weight">
        <%= format_weight(@item.averageweight) %>
      </td>
    </tr>
    """
  end

  defp format_players(item) do
    cond do
      item.minplayers && item.maxplayers && item.minplayers == item.maxplayers ->
        "#{item.minplayers}"
      
      item.minplayers && item.maxplayers ->
        "#{item.minplayers}-#{item.maxplayers}"
      
      item.minplayers ->
        "#{item.minplayers}+"
      
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

  defp truncate_description(description) when is_binary(description) do
    if String.length(description) > 100 do
      String.slice(description, 0, 100) <> "..."
    else
      description
    end
  end

  defp truncate_description(_), do: ""
end