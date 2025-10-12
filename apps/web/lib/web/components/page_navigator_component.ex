defmodule Web.Components.PageNavigatorComponent do
  @moduledoc "BGG-style page navigator component for collection browsing."

  use Phoenix.Component
  import Phoenix.HTML

  def page_navigator(assigns) do
    ~H"""
    <%= if @total_items > @items_per_page do %>
      <div class="infobox">
        <div class="fl">
          {render_page_links(@current_page, max_pages(@total_items, @items_per_page), @username, @filters, @advanced_search)}
        </div>
        <div class="fr">
          <!-- Right side content can be added here if needed -->
        </div>
        <div class="clear"></div>
      </div>
    <% end %>
    """
  end

  defp render_page_links(current_page, total_pages, username, filters, advanced_search) do
    assigns = %{
      current_page: current_page,
      total_pages: total_pages,
      username: username,
      filters: filters,
      advanced_search: advanced_search,
      page_links: build_page_links(current_page, total_pages)
    }

    ~H"""
    <%= for {type, page, text} <- @page_links do %>
      <%= case type do %>
        <% :current -> %>
          <b>{text}</b>
        <% :link -> %>
          <.link patch={build_page_url(@username, @filters, @advanced_search, page)} title={"page #{page}"}>
            {text}
          </.link>
        <% :prev -> %>
          <.link patch={build_page_url(@username, @filters, @advanced_search, page)} title="previous page">
            <b>{text}</b>
          </.link>
        <% :next -> %>
          <.link patch={build_page_url(@username, @filters, @advanced_search, page)} title="next page">
            <b>{text}</b>
          </.link>
        <% :last -> %>
          <.link patch={build_page_url(@username, @filters, @advanced_search, page)} title="last page">
            {text}
          </.link>
        <% :separator -> %>
          {raw(text)}
      <% end %>
    <% end %>
    """
  end

  defp build_page_links(current_page, total_pages) do
    links = []

    # Add Prev link if not on first page
    links =
      if current_page > 1 do
        links ++ [{:prev, current_page - 1, "Prev «"}, {:separator, nil, "&nbsp;&nbsp;"}]
      else
        links
      end

    # Show page range around current page (up to 5 pages total)
    initial_start = max(1, current_page - 2)
    initial_end = min(total_pages, current_page + 2)

    # Adjust range if we're near the beginning or end
    {final_start, final_end} =
      if initial_end - initial_start < 4 do
        if initial_start == 1 do
          {initial_start, min(total_pages, initial_start + 4)}
        else
          {max(1, initial_end - 4), initial_end}
        end
      else
        {initial_start, initial_end}
      end

    page_range = Enum.to_list(final_start..final_end)

    page_links =
      Enum.map(page_range, fn page ->
        if page == current_page do
          {:current, page, "#{page}"}
        else
          {:link, page, "#{page}"}
        end
      end)

    # Add separators between page links (single space comma space)
    page_links_with_separators = Enum.intersperse(page_links, {:separator, nil, " , "})

    links = links ++ page_links_with_separators

    # Add Next link if not on last page
    links =
      if current_page < total_pages do
        separator = [{:separator, nil, "&nbsp;&nbsp;"}]
        next_link = [{:next, current_page + 1, "Next »"}]
        links ++ separator ++ next_link
      else
        links
      end

    links
  end

  defp max_pages(total_items, items_per_page) do
    if total_items == 0 do
      1
    else
      ceil(total_items / items_per_page)
    end
  end

  # Helper function to build page URLs with filters and advanced search preserved
  defp build_page_url(username, filters, advanced_search, page) do
    base_path = "/collection/#{username}"
    
    # Build query parameters
    query_params =
      filters
      |> Enum.filter(fn {_key, value} -> value != nil and value != "" end)
      |> Enum.map(fn {key, value} -> {Atom.to_string(key), value} end)
      |> Enum.into(%{})
    
    # Add page parameter
    query_params = Map.put(query_params, "page", to_string(page))
    
    # Add advanced_search parameter if needed
    query_params =
      if advanced_search do
        Map.put(query_params, "advanced_search", "true")
      else
        query_params
      end
    
    # Build query string
    if Enum.empty?(query_params) do
      base_path
    else
      query_string = URI.encode_query(query_params)
      "#{base_path}?#{query_string}"
    end
  end
end
