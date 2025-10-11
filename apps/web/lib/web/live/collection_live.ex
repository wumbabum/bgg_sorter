defmodule Web.CollectionLive do
  @moduledoc "LiveView for displaying board game collections from BoardGameGeek."

  use Web, :live_view

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
      |> assign(:all_collection_items, [])
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
      |> assign(:all_collection_items, [])
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
          |> assign(:all_collection_items, [])
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

      # Same username, different page
      page != current_page ->
        socket = assign(socket, :current_page, page)
        load_current_page(socket)

      # Same username and page, but advanced_search parameter changed
      advanced_search != socket.assigns.advanced_search ->
        socket =
          socket
          |> assign(:advanced_search, advanced_search)
          |> assign(:filters, filters)

        {:noreply, socket}

      # Same username and page, but filters changed
      filters != current_filters ->
        socket =
          socket
          |> assign(:filters, filters)
          |> assign(:collection_loading, true)
          |> assign(:search_error, nil)

        # Reload collection with new filters - pass filters directly to avoid state timing issues
        send(self(), {:load_collection_with_filters, username, filters})
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
    # Load full collection without filters - we'll filter client-side

    case Core.BggGateway.collection(username, []) do
      {:ok, collection_response} ->
        # Apply client-side filters if any are set
        filtered_items = apply_filters(collection_response.items, filters)
        total_items = length(filtered_items)

        socket =
          socket
          |> assign(:all_collection_items, filtered_items)
          |> assign(:total_items, total_items)
          |> assign(:search_error, nil)

        # Get the current page of items and fetch detailed info for just those
        current_page_items = get_current_page_items(socket)

        case current_page_items do
          [] ->
            # No items to show
            socket =
              socket
              |> assign(:collection_loading, false)
              |> assign(:collection_items, [])

            {:noreply, socket}

          items ->
            # Fetch detailed info for just the current page
            game_ids = Enum.map(items, & &1.id)
            send(self(), {:load_thing_details, game_ids, items})
            {:noreply, socket}
        end

      {:error, reason} ->
        error_message = format_error_message(reason)

        socket =
          socket
          |> assign(:collection_loading, false)
          |> assign(:search_error, error_message)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:load_thing_details, game_ids, basic_items}, socket) do
    case Core.BggGateway.things(game_ids, []) do
      {:ok, detailed_things} ->
        # Merge detailed information with the basic items for current page
        enhanced_items = merge_collection_with_details(basic_items, detailed_things)

        socket =
          socket
          |> assign(:collection_loading, false)
          |> assign(:collection_items, enhanced_items)

        {:noreply, socket}

      {:error, reason} ->
        # If detailed fetch fails, just show basic info for current page
        error_message = "Failed to load detailed information: #{format_error_message(reason)}"

        socket =
          socket
          |> assign(:collection_loading, false)
          # Show basic items
          |> assign(:collection_items, basic_items)
          |> assign(:search_error, error_message)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:load_modal_details, thing_id}, socket) do
    case Core.BggGateway.things([thing_id], []) do
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
        # Same username - apply filters and use push_patch to stay on page
        username == current_username ->
          socket =
            socket
            |> assign(:filters, filters)
            |> assign(:advanced_search, true)
            |> assign(:collection_loading, true)
            |> assign(:search_error, nil)

          # Reload collection with new filters
          send(self(), {:load_collection_with_filters, username, filters})
          {:noreply, push_patch(socket, to: collection_url)}

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
      send(self(), {:load_modal_details, thing_id})
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
    thing_id = socket.assigns.selected_thing.id

    socket =
      socket
      |> assign(:modal_loading, true)
      |> assign(:modal_error, nil)

    send(self(), {:load_modal_details, thing_id})
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

  defp load_current_page(socket) do
    socket = assign(socket, :collection_loading, true)
    current_page_items = get_current_page_items(socket)

    case current_page_items do
      [] ->
        socket =
          socket
          |> assign(:collection_loading, false)
          |> assign(:collection_items, [])

        {:noreply, socket}

      items ->
        game_ids = Enum.map(items, & &1.id)
        send(self(), {:load_thing_details, game_ids, items})
        {:noreply, socket}
    end
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

  defp merge_collection_with_details(collection_items, detailed_things) do
    # Create a map for quick lookup of detailed information by ID
    details_map =
      detailed_things
      |> Enum.map(&{&1.id, &1})
      |> Enum.into(%{})

    # Merge detailed information into collection items
    Enum.map(collection_items, fn item ->
      case Map.get(details_map, item.id) do
        # No detailed info found, keep original
        nil -> item
        detailed -> merge_thing_data(item, detailed)
      end
    end)
  end

  defp merge_thing_data(collection_item, detailed_thing) do
    # Merge the detailed information into the collection item
    %{
      collection_item
      | thumbnail: detailed_thing.thumbnail || collection_item.thumbnail,
        image: detailed_thing.image || collection_item.image,
        description: detailed_thing.description,
        minplayers: detailed_thing.minplayers,
        maxplayers: detailed_thing.maxplayers,
        playingtime: detailed_thing.playingtime,
        minplaytime: detailed_thing.minplaytime,
        maxplaytime: detailed_thing.maxplaytime,
        minage: detailed_thing.minage,
        usersrated: detailed_thing.usersrated,
        average: detailed_thing.average,
        bayesaverage: detailed_thing.bayesaverage,
        rank: detailed_thing.rank,
        owned: detailed_thing.owned,
        averageweight: detailed_thing.averageweight
    }
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
    |> maybe_put_filter(:playingtime_min, Map.get(params, "playingtime_min"))
    |> maybe_put_filter(:playingtime_max, Map.get(params, "playingtime_max"))
    |> maybe_put_filter(:minage, Map.get(params, "minage"))
    |> maybe_put_filter(:average, Map.get(params, "average"))
    |> maybe_put_filter(:rank, Map.get(params, "rank"))
    |> maybe_put_filter(:averageweight_min, Map.get(params, "averageweight_min"))
    |> maybe_put_filter(:averageweight_max, Map.get(params, "averageweight_max"))
    |> maybe_put_filter(:description, Map.get(params, "description"))
  end

  # Apply client-side filters to collection items
  defp apply_filters(items, filters) when filters == %{}, do: items

  defp apply_filters(items, filters) do
    Enum.filter(items, &matches_all_filters?(&1, filters))
  end

  # Check if an item matches all active filters
  defp matches_all_filters?(item, filters) do
    Enum.all?(filters, fn {key, value} ->
      matches_filter?(item, key, value)
    end)
  end

  # Individual filter matching functions
  defp matches_filter?(item, :primary_name, search_term) do
    String.contains?(String.downcase(item.primary_name || ""), String.downcase(search_term))
  end

  defp matches_filter?(item, :yearpublished_min, min_year) do
    case {parse_integer(item.yearpublished), parse_integer(min_year)} do
      {item_year, min_year_int} when is_integer(item_year) and is_integer(min_year_int) ->
        item_year >= min_year_int

      # Skip filter if data is invalid
      _ ->
        true
    end
  end

  defp matches_filter?(item, :yearpublished_max, max_year) do
    case {parse_integer(item.yearpublished), parse_integer(max_year)} do
      {item_year, max_year_int} when is_integer(item_year) and is_integer(max_year_int) ->
        item_year <= max_year_int

      _ ->
        true
    end
  end

  defp matches_filter?(item, :players, target_players) do
    case {parse_integer(item.minplayers), parse_integer(item.maxplayers),
          parse_integer(target_players)} do
      {min_p, max_p, target}
      when is_integer(min_p) and is_integer(max_p) and is_integer(target) ->
        target >= min_p and target <= max_p

      _ ->
        true
    end
  end

  defp matches_filter?(item, :playingtime_min, min_time) do
    case {parse_integer(item.playingtime), parse_integer(min_time)} do
      {item_time, min_time_int} when is_integer(item_time) and is_integer(min_time_int) ->
        item_time >= min_time_int

      _ ->
        true
    end
  end

  defp matches_filter?(item, :playingtime_max, max_time) do
    case {parse_integer(item.playingtime), parse_integer(max_time)} do
      {item_time, max_time_int} when is_integer(item_time) and is_integer(max_time_int) ->
        item_time <= max_time_int

      _ ->
        true
    end
  end

  defp matches_filter?(item, :minage, max_minage) do
    case {parse_integer(item.minage), parse_integer(max_minage)} do
      {item_minage, max_minage_int} when is_integer(item_minage) and is_integer(max_minage_int) ->
        # Game min age should be <= filter (younger or same)
        item_minage <= max_minage_int

      _ ->
        true
    end
  end

  defp matches_filter?(item, :average, min_rating) do
    case {parse_float(item.average), parse_float(min_rating)} do
      {item_rating, min_rating_float} when is_float(item_rating) and is_float(min_rating_float) ->
        item_rating >= min_rating_float

      _ ->
        true
    end
  end

  defp matches_filter?(item, :rank, max_rank) do
    case {parse_integer(item.rank), parse_integer(max_rank)} do
      {item_rank, max_rank_int}
      when is_integer(item_rank) and is_integer(max_rank_int) and item_rank > 0 ->
        # Lower rank number is better
        item_rank <= max_rank_int

      _ ->
        true
    end
  end

  defp matches_filter?(item, :averageweight_min, min_weight) do
    case {parse_float(item.averageweight), parse_float(min_weight)} do
      {item_weight, min_weight_float} when is_float(item_weight) and is_float(min_weight_float) ->
        item_weight >= min_weight_float

      _ ->
        true
    end
  end

  defp matches_filter?(item, :averageweight_max, max_weight) do
    case {parse_float(item.averageweight), parse_float(max_weight)} do
      {item_weight, max_weight_float} when is_float(item_weight) and is_float(max_weight_float) ->
        item_weight <= max_weight_float

      _ ->
        true
    end
  end

  defp matches_filter?(item, :description, search_term) do
    String.contains?(String.downcase(item.description || ""), String.downcase(search_term))
  end

  # Skip unknown filters
  defp matches_filter?(_item, _key, _value), do: true

  # Add non-empty values to filter map
  defp maybe_put_filter(filters, _key, value) when value in [nil, ""], do: filters
  defp maybe_put_filter(filters, key, value), do: Map.put(filters, key, value)

  # Helper functions for parsing
  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int_val, _} -> int_val
      _ -> nil
    end
  end

  defp parse_integer(value) when is_integer(value), do: value
  defp parse_integer(_), do: nil

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float_val, _} -> float_val
      _ -> nil
    end
  end

  defp parse_float(value) when is_float(value), do: value
  defp parse_float(value) when is_integer(value), do: value * 1.0
  defp parse_float(_), do: nil

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
