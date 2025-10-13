defmodule Web.Components.SortableHeaderComponent do
  @moduledoc """
  Component for sortable table headers with triangle indicators and click handlers.
  """
  
  use Phoenix.Component

  @doc """
  Renders a sortable table header with triangle indicators.
  
  ## Attributes
  - field: The field atom this header represents (e.g., :primary_name)
  - label: The display text for the header
  - current_sort_field: The currently active sort field
  - current_sort_direction: The current sort direction (:asc or :desc)
  """
  attr :field, :atom, required: true
  attr :label, :string, required: true
  attr :current_sort_field, :atom, required: true
  attr :current_sort_direction, :atom, required: true

  def sortable_header(assigns) do
    ~H"""
    <th class="sortable-header" phx-click="column_sort" phx-value-field={@field}>
      <div class="sortable-header-content">
        <span class="sortable-header-label"><%= @label %></span>
        <span class="sort-indicator">
          <%= if @field == @current_sort_field do %>
            <%= if @current_sort_direction == :asc do %>
              <span class="triangle triangle-up">▲</span>
            <% else %>
              <span class="triangle triangle-down">▼</span>
            <% end %>
          <% else %>
            <span class="triangle triangle-neutral">▲</span>
          <% end %>
        </span>
      </div>
    </th>
    """
  end
end