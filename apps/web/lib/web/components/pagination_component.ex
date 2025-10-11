defmodule Web.Components.PaginationComponent do
  @moduledoc "Pagination component for browsing collection pages."

  use Phoenix.Component

  def pagination(assigns) do
    ~H"""
    <%= if @total_items > @items_per_page do %>
      <div class="pagination-container">
        <div class="pagination-info">
          Showing {start_item(@current_page, @items_per_page)}-{end_item(
            @current_page,
            @items_per_page,
            @total_items
          )} of {@total_items} games
        </div>

        <div class="pagination-controls">
          <button
            phx-click="prev_page"
            disabled={@current_page == 1}
            class="pagination-btn"
          >
            ← Previous
          </button>

          <span class="page-info">
            Page {@current_page} of {max_pages(@total_items, @items_per_page)}
          </span>

          <button
            phx-click="next_page"
            disabled={@current_page >= max_pages(@total_items, @items_per_page)}
            class="pagination-btn"
          >
            Next →
          </button>
        </div>
      </div>
    <% end %>
    """
  end

  defp start_item(current_page, items_per_page) do
    (current_page - 1) * items_per_page + 1
  end

  defp end_item(current_page, items_per_page, total_items) do
    end_index = current_page * items_per_page
    min(end_index, total_items)
  end

  defp max_pages(total_items, items_per_page) do
    if total_items == 0 do
      1
    else
      ceil(total_items / items_per_page)
    end
  end
end
