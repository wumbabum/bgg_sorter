defmodule Web.CollectionLive do
  @moduledoc "LiveView for displaying board game collections from BoardGameGeek."

  use Web, :live_view

  require Logger

  alias Core.Schemas.{CollectionResponse, Thing}

  @impl true
  def mount(%{"username" => username} = params, _session, socket) do
    # Get page from URL query parameter, default to 1
    page =
      case Map.get(params, "page") do
        page_str when is_binary(page_str) ->
          case Integer.parse(page_str) do
            {page, _} when page > 0 -> page
            _ -> 1
          end

        _ ->
          1
      end

    # Get advanced_search from URL query parameter, default to false
    advanced_search = Map.get(params, "advanced_search") == "true"

    # Parse filter parameters from URL
    filters = parse_url_filters(params)

    socket =
      socket
      |> assign(:username, username)
      |> assign(:collection_loading, true)
      |> assign(:collection_items, [])
      |> assign(:all_collection_items, [])  # Filtered collection for pagination
      |> assign(:original_collection_items, [])  # Unfiltered collection from BGG
      |> assign(:search_error, nil)
      |> assign(:current_page, page)
      |> assign(:items_per_page, 20)
      |> assign(:total_items, 0)
      |> assign(:advanced_search, advanced_search)
      |> assign(:filters, filters)
      |> assign(:modal_open, false)
      |> assign(:modal_loading, false)
      |> assign(:selected_thing, nil)
      |> assign(:thing_details, nil)
      |> assign(:modal_error, nil)

    # Start loading collection in background
    send(self(), {:load_collection, username})

    {:ok, socket}
  end

  @impl true
  def mount(params, _session, socket) do
    # No username provided, show search form or advanced search
    # Get advanced_search from URL query parameter, default to false
    advanced_search = Map.get(params, "advanced_search") == "true"

    socket =
      socket
      |> assign(:username, nil)
      |> assign(:collection_loading, false)
      |> assign(:collection_items, [])
      |> assign(:all_collection_items, [])  # Filtered collection for pagination
      |> assign(:original_collection_items, [])  # Unfiltered collection from BGG
      |> assign(:search_error, nil)
      |> assign(:current_page, 1)
      |> assign(:items_per_page, 20)
      |> assign(:total_items, 0)
      |> assign(:advanced_search, advanced_search)
      |> assign(:filters, %{})
      |> assign(:modal_open, false)
      |> assign(:modal_loading, false)
      |> assign(:selected_thing, nil)
      |> assign(:thing_details, nil)
      |> assign(:modal_error, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"username" => username} = params, _url, socket) do
    # Handle URL parameter changes (like page changes)
    page =
      case Map.get(params, "page") do
        page_str when is_binary(page_str) ->
          case Integer.parse(page_str) do
            {page, _} when page > 0 -> page
            _ -> 1
          end

        _ ->
          1
      end

    # Get advanced_search from URL query parameter, default to false
    advanced_search = Map.get(params, "advanced_search") == "true"

    # Parse filter parameters from URL
    filters = parse_url_filters(params)

    current_page = socket.assigns.current_page
    current_filters = socket.assigns.filters

    cond do
      # Username changed, reload collection
      username != socket.assigns.username ->
        socket =
          socket
          |> assign(:username, username)
          |> assign(:current_page, page)
          |> assign(:collection_loading, true)
          |> assign(:all_collection_items, [])  # Filtered collection for pagination
          |> assign(:original_collection_items, [])  # Unfiltered collection from BGG
          |> assign(:collection_items, [])
          |> assign(:search_error, nil)
          |> assign(:total_items, 0)
          |> assign(:advanced_search, advanced_search)
          |> assign(:filters, filters)
          |> assign(:modal_open, false)
          |> assign(:modal_loading, false)
          |> assign(:selected_thing, nil)
          |> assign(:thing_details, nil)
          |> assign(:modal_error, nil)

        send(self(), {:load_collection, username})
        {:noreply, socket}

      # Filters changed (but same username), try client-side filtering first
      filters != current_filters ->
        socket =
          socket
          |> assign(:current_page, page)  # Also update page
          |> assign(:advanced_search, advanced_search)  # Also update advanced_search
          |> assign(:collection_loading, true)
          |> assign(:search_error, nil)

        case reapply_filters_to_collection(socket, filters) do
          {:ok, updated_socket} ->
            Logger.info("Applied filters client-side without API call")
            {:noreply, updated_socket}
          
          {:reload_needed, socket} ->
            Logger.info("Original collection not available, reloading from API")
            # Reload collection with new filters - pass filters directly to avoid state timing issues
            send(self(), {:load_collection_with_filters, username, filters})
            {:noreply, socket}
        end

      # Same username and filters, but different page - just paginate existing data
      page != current_page ->
        socket =
          socket
          |> assign(:current_page, page)
          |> assign(:advanced_search, advanced_search)  # Update advanced_search if needed
        load_current_page(socket)

      # Same username, filters, and page, but advanced_search parameter changed
      advanced_search != socket.assigns.advanced_search ->
        socket =
          socket
          |> assign(:advanced_search, advanced_search)

        {:noreply, socket}

      # No changes
      true ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    # Handle home page (no username) - check for advanced_search parameter
    advanced_search = Map.get(params, "advanced_search") == "true"
    socket = assign(socket, :advanced_search, advanced_search)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:load_collection, username}, socket) do
    # Load collection using current socket filters
    handle_info({:load_collection_with_filters, username, socket.assigns.filters}, socket)
  end

  @impl true
  def handle_info({:load_collection_with_filters, username, filters}, socket) do
    Logger.info("Loading collection with filters: #{inspect(filters)}")
    # Convert client filters to BGG API parameters
    bgg_params = convert_filters_to_bgg_params(filters)
    Logger.info("BGG API params: #{inspect(bgg_params)}")

    with {:ok, %CollectionResponse{items: basic_items}} <- Core.BggGateway.collection(username, bgg_params),
         {:ok, cached_things} <- Core.BggCacher.load_things_cache(basic_items) do

      Logger.info("Loaded #{length(basic_items)} basic items, got #{length(cached_things)} cached items")

      # Store the original unfiltered collection
      original_items = cached_things
      
      # Apply client-side filtering to complete cached data
      filtered_items = Thing.filter_by(cached_things, filters)
      total_items = length(filtered_items)

      Logger.info("After client-side filtering: #{total_items} items")

      # Get current page items from filtered results
      current_page_items = get_current_page_items_from_list(filtered_items, socket.assigns.current_page)

      socket =
        socket
        |> assign(:original_collection_items, original_items)  # Store original unfiltered data
        |> assign(:all_collection_items, filtered_items)      # Store filtered results for pagination
        |> assign(:collection_items, current_page_items)      # Store current page items
        |> assign(:total_items, total_items)
        |> assign(:collection_loading, false)
        |> assign(:search_error, nil)

      {:noreply, socket}
    else
      {:error, reason} ->
        error_message = format_error_message(reason)
        Logger.warning("Failed to load collection: #{inspect(reason)}")

        socket =
          socket
          |> assign(:collection_loading, false)
          |> assign(:search_error, error_message)

        {:noreply, socket}
    end
  end


  @impl true
  def handle_info({:load_modal_details, thing}, socket) do
    case Core.BggCacher.load_things_cache([thing]) do
      {:ok, [detailed_thing]} ->
        socket =
          socket
          |> assign(:modal_loading, false)
          |> assign(:thing_details, detailed_thing)
          |> assign(:modal_error, nil)

        {:noreply, socket}

      {:ok, []} ->
        socket =
          socket
          |> assign(:modal_loading, false)
          |> assign(:modal_error, "Game details not found")

        {:noreply, socket}

      {:error, reason} ->
        error_message = format_error_message(reason)

        socket =
          socket
          |> assign(:modal_loading, false)
          |> assign(:modal_error, "Failed to load game details: #{error_message}")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("search_collection", %{"username" => username}, socket) do
    # Redirect to /collection/:username
    {:noreply, push_navigate(socket, to: ~p"/collection/#{username}")}
  end

  @impl true
  def handle_event("advanced_search", params, socket) do
    username = Map.get(params, "username")

    if username && username != "" do
      # Extract filters from form parameters for client-side filtering
      filters = extract_game_filters(params)
      current_username = socket.assigns.username

      # Build URL with all filter parameters
      collection_url = build_collection_url(username, filters, advanced_search: true)

      cond do
        # Same username - try client-side filtering first
        username == current_username ->
          socket =
            socket
            |> assign(:advanced_search, true)
            |> assign(:collection_loading, true)
            |> assign(:search_error, nil)

          case reapply_filters_to_collection(socket, filters) do
            {:ok, updated_socket} ->
              Logger.info("Advanced search applied filters client-side without API call")
              {:noreply, push_patch(updated_socket, to: collection_url)}
            
            {:reload_needed, socket} ->
              Logger.info("Original collection not available for advanced search, reloading from API")
              # Reload collection with new filters
              send(self(), {:load_collection_with_filters, username, filters})
              {:noreply, push_patch(socket, to: collection_url)}
          end

        # Different username - need to load new collection
        true ->
          socket =
            socket
            |> assign(:username, username)
            |> assign(:filters, filters)
            |> assign(:advanced_search, true)
            |> assign(:collection_loading, true)
            |> assign(:search_error, nil)
            |> assign(:current_page, 1)
            |> assign(:all_collection_items, [])
            |> assign(:original_collection_items, [])
            |> assign(:collection_items, [])
            |> assign(:total_items, 0)

          # Load new collection
          send(self(), {:load_collection_with_filters, username, filters})
          {:noreply, push_patch(socket, to: collection_url)}
      end
    else
      # No username provided, show error or stay on form
      {:noreply, assign(socket, :search_error, "Please enter a BGG username")}
    end
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    # Clear all filters and reload collection if we have a username
    socket = assign(socket, :filters, %{})

    case socket.assigns.username do
      nil ->
        {:noreply, socket}

      username ->
        socket =
          socket
          |> assign(:collection_loading, true)
          |> assign(:search_error, nil)

        # Build URL without filter parameters but keeping advanced_search if active
        url =
          if socket.assigns.advanced_search do
            "/collection/#{username}?advanced_search=true"
          else
            "/collection/#{username}"
          end

        send(self(), {:load_collection, username})
        {:noreply, push_patch(socket, to: url)}
    end
  end

  @impl true
  def handle_event("retry_search", _params, socket) do
    username = socket.assigns.username

    socket =
      socket
      |> assign(:collection_loading, true)
      |> assign(:search_error, nil)

    send(self(), {:load_collection, username})

    {:noreply, socket}
  end

  @impl true
  def handle_event("goto_page", %{"page" => page_str}, socket) do
    case Integer.parse(page_str) do
      {page, _} when page > 0 ->
        username = socket.assigns.username
        filters = socket.assigns.filters
        advanced_search = socket.assigns.advanced_search

        url =
          build_collection_url(username, filters,
            page: page,
            advanced_search: advanced_search
          )

        {:noreply, push_patch(socket, to: url)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("next_page", _params, socket) do
    max_page = max_page(socket)
    current_page = socket.assigns.current_page
    username = socket.assigns.username
    filters = socket.assigns.filters
    advanced_search = socket.assigns.advanced_search

    if current_page < max_page do
      next_page = current_page + 1

      url =
        build_collection_url(username, filters,
          page: next_page,
          advanced_search: advanced_search
        )

      {:noreply, push_patch(socket, to: url)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("prev_page", _params, socket) do
    current_page = socket.assigns.current_page
    username = socket.assigns.username
    filters = socket.assigns.filters
    advanced_search = socket.assigns.advanced_search

    if current_page > 1 do
      prev_page = current_page - 1

      url =
        build_collection_url(username, filters,
          page: prev_page,
          advanced_search: advanced_search
        )

      {:noreply, push_patch(socket, to: url)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("open_thing_modal", %{"thing_id" => thing_id}, socket) do
    # Find the selected thing from current page items
    selected_thing = Enum.find(socket.assigns.collection_items, &(&1.id == thing_id))

    if selected_thing do
      socket =
        socket
        |> assign(:modal_open, true)
        |> assign(:modal_loading, true)
        |> assign(:selected_thing, selected_thing)
        |> assign(:thing_details, nil)
        |> assign(:modal_error, nil)

      # Load detailed information for this specific thing
      send(self(), {:load_modal_details, selected_thing})
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    socket =
      socket
      |> assign(:modal_open, false)
      |> assign(:modal_loading, false)
      |> assign(:selected_thing, nil)
      |> assign(:thing_details, nil)
      |> assign(:modal_error, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("stop_propagation", _params, socket) do
    # Prevent modal from closing when clicking inside modal content
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_advanced_search", _params, socket) do
    current_advanced_search = socket.assigns.advanced_search
    new_advanced_search = !current_advanced_search

    case socket.assigns.username do
      nil ->
        # No username, navigate to advanced search page
        {:noreply, push_navigate(socket, to: "/collection?advanced_search=true")}

      username ->
        # Have username and collection data, just toggle advanced search with push_patch
        new_url =
          if new_advanced_search do
            "/collection/#{username}?advanced_search=true"
          else
            "/collection/#{username}"
          end

        # Use push_patch to update URL without losing data
        socket = assign(socket, :advanced_search, new_advanced_search)
        {:noreply, push_patch(socket, to: new_url)}
    end
  end

  @impl true
  def handle_event("retry_modal", _params, socket) do
    socket =
      socket
      |> assign(:modal_loading, true)
      |> assign(:modal_error, nil)

    send(self(), {:load_modal_details, socket.assigns.selected_thing})
    {:noreply, socket}
  end

  defp get_current_page_items(socket) do
    all_items = socket.assigns.all_collection_items
    current_page = socket.assigns.current_page
    items_per_page = socket.assigns.items_per_page

    start_index = (current_page - 1) * items_per_page

    all_items
    |> Enum.drop(start_index)
    |> Enum.take(items_per_page)
  end

  defp get_current_page_items_from_list(all_items, current_page) do
    items_per_page = 20
    start_index = (current_page - 1) * items_per_page

    all_items
    |> Enum.drop(start_index)
    |> Enum.take(items_per_page)
  end

  defp load_current_page(socket) do
    # With caching, we already have all data and just need to paginate
    current_page_items = get_current_page_items(socket)

    socket =
      socket
      |> assign(:collection_loading, false)
      |> assign(:collection_items, current_page_items)

    {:noreply, socket}
  end

  defp max_page(socket) do
    total_items = socket.assigns.total_items
    items_per_page = socket.assigns.items_per_page

    if total_items == 0 do
      1
    else
      ceil(total_items / items_per_page)
    end
  end


  defp format_error_message(:invalid_username), do: "Invalid username specified"
  defp format_error_message(:user_not_found), do: "User not found"
  defp format_error_message(:network_error), do: "Network error - please try again"
  defp format_error_message(:timeout), do: "Request timed out - please try again"
  defp format_error_message(reason) when is_binary(reason), do: reason

  defp format_error_message({:invalid_collection_request, errors}) do
    "Invalid search parameters: #{format_validation_errors(errors)}"
  end

  defp format_error_message(_), do: "An unexpected error occurred"

  defp format_validation_errors(errors) do
    errors
    |> Enum.map(fn {field, {message, _}} -> "#{field} #{message}" end)
    |> Enum.join(", ")
  end

  # Extract filters from form parameters for client-side filtering
  defp extract_game_filters(params) do
    %{}
    |> maybe_put_filter(:primary_name, Map.get(params, "primary_name"))
    |> maybe_put_filter(:yearpublished_min, Map.get(params, "yearpublished_min"))
    |> maybe_put_filter(:yearpublished_max, Map.get(params, "yearpublished_max"))
    |> maybe_put_filter(:players, Map.get(params, "players"))
    |> maybe_put_filter(:playingtime, Map.get(params, "playingtime"))
    |> maybe_put_filter(:minage, Map.get(params, "minage"))
    |> maybe_put_filter(:average, Map.get(params, "average"))
    |> maybe_put_filter(:rank, Map.get(params, "rank"))
    |> maybe_put_filter(:averageweight_min, Map.get(params, "averageweight_min"))
    |> maybe_put_filter(:averageweight_max, Map.get(params, "averageweight_max"))
    |> maybe_put_filter(:description, Map.get(params, "description"))
  end

  # Convert client-side filters to BGG API collection parameters
  defp convert_filters_to_bgg_params(filters) do
    IO.inspect(filters, label: "Converting filters to BGG params")
    # Start with default parameters
    bgg_params = [stats: 1]

    # Convert supported filters to BGG API parameters
    bgg_params
    |> maybe_add_bgg_param("minbggrating", Map.get(filters, :average))
    |> maybe_add_bgg_param("own", get_ownership_filter(filters))
  end

  # Helper to add BGG API parameter if filter value exists
  defp maybe_add_bgg_param(params, _key, value) when value in [nil, ""], do: params
  defp maybe_add_bgg_param(params, key, value) do
    Keyword.put(params, String.to_atom(key), value)
  end

  # Determine ownership filter - default to owned games (own: 1)
  defp get_ownership_filter(_filters) do
    # For now, always filter to owned games as this is the most common use case
    # Could be made configurable in the future
    1
  end


  # Reapply filters to existing collection without API call
  defp reapply_filters_to_collection(socket, new_filters) do
    original_items = socket.assigns.original_collection_items
    
    # If we don't have original collection data, fall back to API reload
    if Enum.empty?(original_items) do
      {:reload_needed, socket}
    else
      # Apply new filters to original collection
      filtered_items = Thing.filter_by(original_items, new_filters)
      total_items = length(filtered_items)
      
      # Reset to page 1 when filters change
      current_page = 1
      current_page_items = get_current_page_items_from_list(filtered_items, current_page)
      
      updated_socket =
        socket
        |> assign(:filters, new_filters)
        |> assign(:all_collection_items, filtered_items)
        |> assign(:collection_items, current_page_items)
        |> assign(:current_page, current_page)
        |> assign(:total_items, total_items)
        |> assign(:collection_loading, false)
        |> assign(:search_error, nil)
      
      {:ok, updated_socket}
    end
  end

  # Add non-empty values to filter map
  defp maybe_put_filter(filters, _key, value) when value in [nil, ""], do: filters
  defp maybe_put_filter(filters, key, value), do: Map.put(filters, key, value)




  # Helper function to parse URL parameters into filters
  defp parse_url_filters(params) do
    %{}
    |> maybe_put_filter(:primary_name, Map.get(params, "primary_name"))
    |> maybe_put_filter(:yearpublished_min, Map.get(params, "yearpublished_min"))
    |> maybe_put_filter(:yearpublished_max, Map.get(params, "yearpublished_max"))
    |> maybe_put_filter(:players, Map.get(params, "players"))
    |> maybe_put_filter(:playingtime_min, Map.get(params, "playingtime_min"))
    |> maybe_put_filter(:playingtime_max, Map.get(params, "playingtime_max"))
    |> maybe_put_filter(:minage, Map.get(params, "minage"))
    |> maybe_put_filter(:average, Map.get(params, "average"))
    |> maybe_put_filter(:rank, Map.get(params, "rank"))
    |> maybe_put_filter(:averageweight_min, Map.get(params, "averageweight_min"))
    |> maybe_put_filter(:averageweight_max, Map.get(params, "averageweight_max"))
    |> maybe_put_filter(:description, Map.get(params, "description"))
  end

  # Helper function to build URL with filter query parameters
  defp build_collection_url(username, filters, opts) do
    base_path = "/collection/#{username}"

    # Build query parameters
    query_params =
      filters
      |> Enum.filter(fn {_key, value} -> value != nil and value != "" end)
      |> Enum.map(fn {key, value} -> {Atom.to_string(key), value} end)
      |> Enum.into(%{})

    # Add advanced_search parameter if needed
    query_params =
      if opts[:advanced_search] do
        Map.put(query_params, "advanced_search", "true")
      else
        query_params
      end

    # Add page parameter if needed
    query_params =
      if opts[:page] do
        Map.put(query_params, "page", to_string(opts[:page]))
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
