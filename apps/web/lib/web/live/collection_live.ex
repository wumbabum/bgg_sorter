defmodule Web.CollectionLive do
  @moduledoc "LiveView for displaying board game collections from BoardGameGeek."

  use Web, :live_view

  require Logger
  import Ecto.Query

  alias Core.Schemas.CollectionResponse

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

    # Parse sort parameters from URL
    {sort_field, sort_direction} = parse_sort_params(params)

    # Parse modal parameter from URL
    modal_thing_id = Map.get(params, "modal_thing_id")
    
    # Parse selected mechanics from URL
    selected_mechanics = parse_selected_mechanics(params)

    socket =
      socket
      |> assign(:username, username)
      |> assign(:collection_loading, true)
      |> assign(:collection_items, [])
      # Filtered collection for pagination
      |> assign(:all_collection_items, [])
      # Unfiltered collection from BGG
      |> assign(:original_collection_items, [])
      |> assign(:search_error, nil)
      |> assign(:current_page, page)
      |> assign(:items_per_page, 20)
      |> assign(:total_items, 0)
      |> assign(:advanced_search, advanced_search)
      |> assign(:filters, filters)
      |> assign(:sort_by, sort_field)
      |> assign(:sort_direction, sort_direction)
      |> assign(:modal_open, false)
      |> assign(:modal_loading, false)
      |> assign(:selected_thing, nil)
      |> assign(:thing_details, nil)
      |> assign(:modal_error, nil)
      |> assign(:modal_thing_id, nil)
      |> assign(:selected_mechanics, MapSet.new())
      |> assign(:all_mechanics_expanded, false)
      |> assign(:popular_mechanics, [])
      |> assign(:mechanics_loading, false)
      |> assign(:mechanics_search_query, "")
      |> assign(:mechanics_search_results, [])

    # Check for modal_thing_id and set up modal state
    socket =
      if modal_thing_id && modal_thing_id != "" do
        socket
        |> assign(:modal_open, true)
        |> assign(:modal_loading, true)
        |> assign(:modal_thing_id, modal_thing_id)
        |> assign(:selected_mechanics, selected_mechanics)
      else
        socket
        |> assign(:modal_thing_id, nil)
        |> assign(:selected_mechanics, selected_mechanics)
      end

    # Start loading collection in background
    send(self(), {:load_collection, username})

    # If modal_thing_id is present, also trigger modal loading
    if modal_thing_id && modal_thing_id != "" do
      send(self(), {:load_modal_details_by_id, modal_thing_id})
    end

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
      # Filtered collection for pagination
      |> assign(:all_collection_items, [])
      # Unfiltered collection from BGG
      |> assign(:original_collection_items, [])
      |> assign(:search_error, nil)
      |> assign(:current_page, 1)
      |> assign(:items_per_page, 20)
      |> assign(:total_items, 0)
      |> assign(:advanced_search, advanced_search)
      |> assign(:filters, %{})
      |> assign(:sort_by, :primary_name)
      |> assign(:sort_direction, :asc)
      |> assign(:modal_open, false)
      |> assign(:modal_loading, false)
      |> assign(:selected_thing, nil)
      |> assign(:thing_details, nil)
      |> assign(:modal_error, nil)
      |> assign(:modal_thing_id, nil)
      |> assign(:selected_mechanics, MapSet.new())
      |> assign(:all_mechanics_expanded, false)
      |> assign(:popular_mechanics, [])
      |> assign(:mechanics_loading, false)
      |> assign(:mechanics_search_query, "")
      |> assign(:mechanics_search_results, [])

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

    # Parse sort parameters from URL
    {sort_field, sort_direction} = parse_sort_params(params)

    # Parse modal parameter from URL
    modal_thing_id = Map.get(params, "modal_thing_id")
    
    # Parse selected mechanics from URL
    selected_mechanics = parse_selected_mechanics(params)

    current_page = socket.assigns.current_page
    current_filters = socket.assigns.filters
    current_sort_field = socket.assigns.sort_by
    current_sort_direction = socket.assigns.sort_direction
    current_modal_thing_id = socket.assigns.modal_thing_id
    current_selected_mechanics = socket.assigns.selected_mechanics

    Logger.info("🔍 MECHANICS DEBUG: URL mechanics: #{inspect(MapSet.to_list(selected_mechanics))}")
    Logger.info("🔍 MECHANICS DEBUG: Current mechanics: #{inspect(MapSet.to_list(current_selected_mechanics))}")

    cond do
      # Username changed, reload collection
      username != socket.assigns.username ->
        socket =
          socket
          |> assign(:username, username)
          |> assign(:current_page, page)
          |> assign(:collection_loading, true)
          # Filtered collection for pagination
          |> assign(:all_collection_items, [])
          # Unfiltered collection from BGG
          |> assign(:original_collection_items, [])
          |> assign(:collection_items, [])
          |> assign(:search_error, nil)
          |> assign(:total_items, 0)
          |> assign(:advanced_search, advanced_search)
          |> assign(:filters, filters)
          |> assign(:sort_by, sort_field)
          |> assign(:sort_direction, sort_direction)
          |> assign(:modal_open, false)
          |> assign(:modal_loading, false)
          |> assign(:selected_thing, nil)
          |> assign(:thing_details, nil)
          |> assign(:modal_error, nil)
          |> assign(:modal_thing_id, modal_thing_id)
          |> assign(:selected_mechanics, selected_mechanics)

        # Check for modal_thing_id and set up modal state
        socket =
          if modal_thing_id && modal_thing_id != "" do
            socket
            |> assign(:modal_open, true)
            |> assign(:modal_loading, true)
          else
            socket
          end

        send(self(), {:load_collection, username})
        
        # If modal_thing_id is present, trigger modal loading
        if modal_thing_id && modal_thing_id != "" do
          send(self(), {:load_modal_details_by_id, modal_thing_id})
        end
        
        {:noreply, socket}

      # Filters changed (but same username), try client-side filtering first
      filters != current_filters ->
        socket =
          socket
          # Also update page
          |> assign(:current_page, page)
          # Also update advanced_search
          |> assign(:advanced_search, advanced_search)
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

      # Selected mechanics changed - apply client-side filtering
      selected_mechanics != current_selected_mechanics ->
        Logger.info("🔍 MECHANICS DEBUG: Mechanics changed, applying client-side filtering")
        socket =
          socket
          |> assign(:selected_mechanics, selected_mechanics)
          |> assign(:advanced_search, advanced_search)
          |> apply_mechanics_filtering()
          # Reset to page 1 when filtering changes
          |> assign(:current_page, 1)
        
        {:noreply, socket}
      
      # Sort parameters changed - reload with new database sorting
      sort_field != current_sort_field or sort_direction != current_sort_direction ->
        socket =
          socket
          |> assign(:sort_by, sort_field)
          |> assign(:sort_direction, sort_direction)
          # Reset to page 1
          |> assign(:current_page, 1)
          |> assign(:advanced_search, advanced_search)
          |> assign(:collection_loading, true)
          |> assign(:search_error, nil)

        # Reload collection with new sort parameters
        send(self(), {:load_collection_with_filters, username, filters})
        {:noreply, socket}

      # Same username and filters, but different page - just paginate existing data
      page != current_page ->
        socket =
          socket
          |> assign(:current_page, page)
          # Update advanced_search if needed
          |> assign(:advanced_search, advanced_search)
          # Update sort parameters
          |> assign(:sort_by, sort_field)
          |> assign(:sort_direction, sort_direction)

        load_current_page(socket)

      # Modal thing ID changed - handle modal state
      modal_thing_id != current_modal_thing_id ->
        socket =
          if modal_thing_id && modal_thing_id != "" do
            socket
            |> assign(:modal_open, true)
            |> assign(:modal_loading, true)
            |> assign(:modal_thing_id, modal_thing_id)
            |> assign(:selected_thing, nil)
            |> assign(:thing_details, nil)
            |> assign(:modal_error, nil)
            |> assign(:advanced_search, advanced_search)
          else
            socket
            |> assign(:modal_open, false)
            |> assign(:modal_loading, false)
            |> assign(:modal_thing_id, nil)
            |> assign(:selected_thing, nil)
            |> assign(:thing_details, nil)
            |> assign(:modal_error, nil)
            |> assign(:advanced_search, advanced_search)
          end

        # Trigger modal loading if needed
        if modal_thing_id && modal_thing_id != "" do
          send(self(), {:load_modal_details_by_id, modal_thing_id})
        end
        
        {:noreply, socket}

      # Same username, filters, and page, but advanced_search parameter changed
      advanced_search != socket.assigns.advanced_search ->
        socket =
          socket
          |> assign(:advanced_search, advanced_search)
          |> assign(:modal_thing_id, modal_thing_id)

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
    modal_thing_id = Map.get(params, "modal_thing_id")
    
    socket = 
      socket
      |> assign(:advanced_search, advanced_search)
      |> assign(:modal_thing_id, modal_thing_id)
      
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

    # Extract client-only filters (those not supported by BGG API)
    client_filters = extract_client_only_filters(filters)
    
    # Note: Mechanics filtering is now done client-side, not passed to server
    Logger.info("🔍 MECHANICS DEBUG: Selected mechanics will be applied client-side: #{inspect(MapSet.to_list(socket.assigns.selected_mechanics))}")

    with {:ok, %CollectionResponse{items: basic_items}} <-
           Core.BggGateway.collection(username, bgg_params),
         {:ok, cached_things} <-
           Core.BggCacher.load_things_cache(
             basic_items,
             client_filters,
             socket.assigns.sort_by,
             socket.assigns.sort_direction
           ) do
      Logger.info(
        "Loaded #{length(basic_items)} basic items, got #{length(cached_things)} cached items with database filtering"
      )

      # Store the original unfiltered collection (for client-side mechanics filtering)
      original_items = cached_things
      Logger.info("Loaded #{length(original_items)} items from database")

      socket =
        socket
        # Store original unfiltered data
        |> assign(:original_collection_items, original_items)
        |> assign(:collection_loading, false)
        |> assign(:search_error, nil)
        # Apply mechanics filtering client-side
        |> apply_mechanics_filtering()

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
  def handle_info({:load_modal_details_by_id, thing_id}, socket) do
    Logger.info("🔍 MODAL DEBUG: Loading modal details for thing_id: #{inspect(thing_id)}")
    
    # Try to parse the thing_id
    case Integer.parse(to_string(thing_id)) do
      {parsed_id, _} ->
        Logger.info("🔍 MODAL DEBUG: Parsed thing_id as: #{parsed_id}")
        # Create a minimal thing struct to query with
        minimal_thing = %{id: to_string(parsed_id)}
        Logger.info("🔍 MODAL DEBUG: Created minimal_thing: #{inspect(minimal_thing)}")
        
        case Core.BggCacher.load_things_cache([minimal_thing]) do
          {:ok, [detailed_thing]} ->
            Logger.info("🔍 MODAL DEBUG: Loaded detailed thing: #{inspect(detailed_thing.primary_name)}")
            Logger.info("🔍 MODAL DEBUG: Thing mechanics raw: #{inspect(detailed_thing.mechanics)}")
            Logger.info("🔍 MODAL DEBUG: Mechanics count: #{length(detailed_thing.mechanics || [])}")
            Logger.info("🔍 MODAL DEBUG: Mechanics association loaded? #{inspect(!match?(%Ecto.Association.NotLoaded{}, detailed_thing.mechanics))}")
            if detailed_thing.mechanics && length(detailed_thing.mechanics) > 0 do
              Logger.info("🔍 MODAL DEBUG: First mechanic: #{inspect(Enum.at(detailed_thing.mechanics, 0).name)}")
              Logger.info("🔍 MODAL DEBUG: All mechanic names: #{inspect(Enum.map(detailed_thing.mechanics, & &1.name))}")
            end
            
            socket =
              socket
              |> assign(:modal_loading, false)
              |> assign(:thing_details, detailed_thing)
              |> assign(:selected_thing, detailed_thing)
              |> assign(:modal_error, nil)

            {:noreply, socket}

          {:ok, []} ->
            socket =
              socket
              |> assign(:modal_loading, false)
              |> assign(:modal_error, "Game not found in your collection")

            {:noreply, socket}

          {:error, reason} ->
            error_message = format_error_message(reason)

            socket =
              socket
              |> assign(:modal_loading, false)
              |> assign(:modal_error, "Failed to load game details: #{error_message}")

            {:noreply, socket}
        end
        
      :error ->
        socket =
          socket
          |> assign(:modal_loading, false)
          |> assign(:modal_error, "Invalid game ID format")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:load_modal_details, thing}, socket) do
    Logger.info("Loading modal details for thing: #{inspect(thing.primary_name)} (ID: #{thing.id})")
    
    case Core.BggCacher.load_things_cache([thing]) do
      {:ok, [detailed_thing]} ->
        Logger.info("Loaded detailed thing: #{inspect(detailed_thing.primary_name)}")
        Logger.info("Thing mechanics: #{inspect(detailed_thing.mechanics)}")
        Logger.info("Mechanics count: #{length(detailed_thing.mechanics || [])}")
        
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
              Logger.info(
                "Original collection not available for advanced search, reloading from API"
              )

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
        |> assign(:modal_thing_id, thing_id)

      # Update URL to include modal_thing_id
      case socket.assigns.username do
        nil ->
          # No username case - shouldn't normally happen
          send(self(), {:load_modal_details, selected_thing})
          {:noreply, socket}
          
        username ->
          filters = socket.assigns.filters
          advanced_search = socket.assigns.advanced_search
          current_page = socket.assigns.current_page
          sort_field = socket.assigns.sort_by
          sort_direction = socket.assigns.sort_direction
          
          url =
            build_collection_url_with_sort(username, filters, sort_field, sort_direction,
              page: current_page,
              advanced_search: advanced_search,
              modal_thing_id: thing_id
            )
          
          # Load detailed information for this specific thing
          send(self(), {:load_modal_details, selected_thing})
          {:noreply, push_patch(socket, to: url)}
      end
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
      |> assign(:modal_thing_id, nil)

    # Remove modal_thing_id from URL while preserving other parameters
    case socket.assigns.username do
      nil ->
        # No username, build URL without modal_thing_id
        url =
          if socket.assigns.advanced_search do
            "/collection?advanced_search=true"
          else
            "/collection"
          end
        
        {:noreply, push_patch(socket, to: url)}
        
      username ->
        # Have username, build URL with all parameters except modal_thing_id
        filters = socket.assigns.filters
        advanced_search = socket.assigns.advanced_search
        current_page = socket.assigns.current_page
        sort_field = socket.assigns.sort_by
        sort_direction = socket.assigns.sort_direction
        
        url =
          build_collection_url_with_sort_and_page(username, filters, sort_field, sort_direction,
            page: current_page,
            advanced_search: advanced_search
          )
        
        {:noreply, push_patch(socket, to: url)}
    end
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

  
  @impl true
  def handle_event("search_mechanics", %{"value" => query}, socket) do
    Logger.info("Searching mechanics with query: #{inspect(query)}")
    
    socket = 
      socket
      |> assign(:mechanics_search_query, query)
      |> assign(:mechanics_search_results, search_mechanics_by_query(query))
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_mechanic", %{"mechanic_id" => "all"}, socket) do
    # "All" toggles the mechanics expansion, doesn't clear selection
    current_expanded = Map.get(socket.assigns, :all_mechanics_expanded, false)
    new_expanded = !current_expanded
    
    Logger.info("🔍 MECHANICS DEBUG: Toggling mechanics expansion: #{new_expanded}")
    
    socket = assign(socket, :all_mechanics_expanded, new_expanded)
    
    # Load popular mechanics if expanding and not already loaded
    socket = 
      if new_expanded and Enum.empty?(socket.assigns.popular_mechanics) do
        Logger.info("Loading popular mechanics")
        # Set loading state first
        socket = assign(socket, :mechanics_loading, true)
        
        try do
          # First check if there are any mechanics at all
          total_mechanics = Core.Repo.aggregate(Core.Schemas.Mechanic, :count)
          Logger.info("🔍 MECHANICS DEBUG: Total mechanics in database: #{total_mechanics}")
          
          # Check if there are any thing_mechanics associations
          total_associations = Core.Repo.aggregate(Core.Schemas.ThingMechanic, :count)
          Logger.info("🔍 MECHANICS DEBUG: Total thing_mechanic associations: #{total_associations}")
          
          popular_mechanics = Core.Repo.all(Core.Schemas.Mechanic.most_popular(50))
          Logger.info("🔍 MECHANICS DEBUG: Loaded #{length(popular_mechanics)} popular mechanics")
          
          # If no popular mechanics found, try loading seeded mechanics alphabetically
          final_mechanics = 
            if Enum.empty?(popular_mechanics) do
              Logger.info("🔍 MECHANICS DEBUG: No popular mechanics, loading 50 seeded mechanics alphabetically")
              Core.Repo.all(from m in Core.Schemas.Mechanic, limit: 50, order_by: m.name)
            else
              popular_mechanics
            end
          
          socket
          |> assign(:popular_mechanics, final_mechanics)
          |> assign(:mechanics_loading, false)
        rescue
          error ->
            Logger.error("Failed to load popular mechanics: #{inspect(error)}")
            # Try to load any mechanics as fallback
            fallback_mechanics = 
              try do
                Core.Repo.all(from m in Core.Schemas.Mechanic, limit: 50, order_by: m.name)
              rescue
                _ -> []
              end
            Logger.info("🔍 MECHANICS DEBUG: Fallback loaded #{length(fallback_mechanics)} mechanics")
            socket
            |> assign(:popular_mechanics, fallback_mechanics)
            |> assign(:mechanics_loading, false)
        end
      else
        socket
      end
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("toggle_mechanic", %{"mechanic_id" => mechanic_id}, socket) do
    Logger.info("🔍 MECHANICS DEBUG: Mechanic toggled: #{inspect(mechanic_id)}")
    
    # Toggle mechanic in selected_mechanics set
    current_selected = socket.assigns.selected_mechanics
    Logger.info("🔍 MECHANICS DEBUG: Current selected: #{inspect(MapSet.to_list(current_selected))}")
    
    new_selected = 
      if MapSet.member?(current_selected, mechanic_id) do
        Logger.info("🔍 MECHANICS DEBUG: Removing mechanic #{mechanic_id}")
        MapSet.delete(current_selected, mechanic_id)
      else
        Logger.info("🔍 MECHANICS DEBUG: Adding mechanic #{mechanic_id}")
        MapSet.put(current_selected, mechanic_id)
      end
    
    Logger.info("🔍 MECHANICS DEBUG: New selected: #{inspect(MapSet.to_list(new_selected))}")
    
    socket = 
      socket
      |> assign(:selected_mechanics, new_selected)
      |> apply_mechanics_filtering()
      |> assign(:current_page, 1)  # Reset to page 1 when filtering changes
    
    # Update URL to include selected mechanics - build new URL with mechanics parameter
    case socket.assigns.username do
      nil ->
        {:noreply, socket}
        
      username ->
        filters = socket.assigns.filters
        advanced_search = socket.assigns.advanced_search
        sort_field = socket.assigns.sort_by
        sort_direction = socket.assigns.sort_direction
        modal_thing_id = socket.assigns.modal_thing_id
        
        url = build_collection_url_with_mechanics(
          username, filters, sort_field, sort_direction, new_selected,
          page: 1,  # Always reset to page 1 when filtering
          advanced_search: advanced_search,
          modal_thing_id: modal_thing_id
        )
        
        {:noreply, push_patch(socket, to: url)}
    end
  end

  @impl true
  def handle_event("column_sort", %{"field" => field_str}, socket) do
    field = String.to_atom(field_str)
    current_sort_field = socket.assigns.sort_by
    current_sort_direction = socket.assigns.sort_direction

    # Determine new sort direction
    new_sort_direction =
      if field == current_sort_field do
        # Same field clicked - toggle direction
        case current_sort_direction do
          :asc -> :desc
          :desc -> :asc
        end
      else
        # Different field clicked - default to ascending
        :asc
      end

    # Update URL to include sort parameters (this will trigger handle_params with new sort)
    username = socket.assigns.username
    filters = socket.assigns.filters
    advanced_search = socket.assigns.advanced_search

    url =
      build_collection_url_with_sort(username, filters, field, new_sort_direction,
        advanced_search: advanced_search
      )

    {:noreply, push_patch(socket, to: url)}
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
    # Handle nested weight parameters from range_input component
    weight_params = Map.get(params, "averageweight", %{})
    weight_min = Map.get(weight_params, "min")
    weight_max = Map.get(weight_params, "max")

    %{}
    |> maybe_put_filter(:primary_name, Map.get(params, "primary_name"))
    |> maybe_put_filter(:players, Map.get(params, "players"))
    |> maybe_put_filter(:playingtime, Map.get(params, "playingtime"))
    |> maybe_put_filter(:average, Map.get(params, "average"))
    |> maybe_put_filter(:rank, Map.get(params, "rank"))
    |> put_weight_filters(weight_min, weight_max)
    |> maybe_put_filter(:description, Map.get(params, "description"))
    |> put_mechanics_filters(Map.get(params, "mechanics"))
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

  # Extract filters that should be applied at database level (not supported by BGG API)
  defp extract_client_only_filters(filters) do
    # These filters are applied at database level for better performance
    client_only_keys = [
      :primary_name,
      :players,
      :playingtime,
      :rank,
      :averageweight_min,
      :averageweight_max,
      :description,
      :selected_mechanics
    ]

    Map.take(filters, client_only_keys)
  end

  # Always reload with database-level filtering and sorting
  defp reapply_filters_to_collection(socket, _new_filters) do
    # Since we've moved to database-level operations, always reload
    # This ensures filters and sorting are applied consistently at the database level
    {:reload_needed, socket}
  end

  # Add non-empty values to filter map
  defp maybe_put_filter(filters, _key, value) when value in [nil, ""], do: filters
  defp maybe_put_filter(filters, key, value), do: Map.put(filters, key, value)

  # Always put weight filters (even if nil/empty) and let Thing.filter_by handle defaults
  defp put_weight_filters(filters, min_weight, max_weight) do
    filters
    |> Map.put(:averageweight_min, min_weight)
    |> Map.put(:averageweight_max, max_weight)
  end
  
  # Put mechanics filters from comma-separated string or MapSet
  defp put_mechanics_filters(filters, mechanics_str) when is_binary(mechanics_str) and mechanics_str != "" do
    mechanic_ids = 
      mechanics_str
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
    
    if Enum.empty?(mechanic_ids) do
      filters
    else
      Map.put(filters, :selected_mechanics, mechanic_ids)
    end
  end
  
  # Handle MapSet from selected_mechanics state
  defp put_mechanics_filters(filters, %MapSet{} = mechanics_set) do
    mechanic_ids = MapSet.to_list(mechanics_set)
    if Enum.empty?(mechanic_ids) do
      filters
    else
      Map.put(filters, :selected_mechanics, mechanic_ids)
    end
  end
  
  defp put_mechanics_filters(filters, _), do: filters
  
  # Search mechanics by name query
  defp search_mechanics_by_query(query) when is_binary(query) and query != "" do
    trimmed_query = String.trim(query)
    if String.length(trimmed_query) >= 2 do
      like_pattern = "%" <> trimmed_query <> "%"
      Core.Repo.all(
        from m in Core.Schemas.Mechanic,
          where: ilike(m.name, ^like_pattern),
          order_by: m.name,
          limit: 15
      )
    else
      []
    end
  end
  
  defp search_mechanics_by_query(_), do: []
  
  # Parse selected mechanics from URL parameters
  defp parse_selected_mechanics(params) do
    case Map.get(params, "mechanics") do
      mechanics_str when is_binary(mechanics_str) and mechanics_str != "" ->
        Logger.info("Parsing mechanics from URL: #{inspect(mechanics_str)}")
        selected = 
          mechanics_str
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> MapSet.new()
        Logger.info("Parsed selected mechanics: #{inspect(MapSet.to_list(selected))}")
        selected
        
      _ ->
        MapSet.new()
    end
  end
  
  # Encode selected mechanics for URL
  defp encode_selected_mechanics(%MapSet{} = selected_mechanics) do
    mechanics_list = MapSet.to_list(selected_mechanics)
    if Enum.empty?(mechanics_list) do
      ""
    else
      Enum.join(mechanics_list, ",")
    end
  end
  
  # Apply mechanics filtering to the collection client-side
  defp apply_mechanics_filtering(socket) do
    original_items = socket.assigns.original_collection_items
    selected_mechanics = socket.assigns.selected_mechanics
    
    Logger.info("🔍 MECHANICS DEBUG: Applying client-side filtering to #{length(original_items)} items")
    Logger.info("🔍 MECHANICS DEBUG: Selected mechanics: #{inspect(MapSet.to_list(selected_mechanics))}")
    
    filtered_items = 
      if MapSet.size(selected_mechanics) == 0 do
        # No mechanics filter - show all items
        Logger.info("🔍 MECHANICS DEBUG: No mechanics selected, showing all items")
        original_items
      else
        # Filter items that have ALL selected mechanics
        mechanic_ids = MapSet.to_list(selected_mechanics)
        Logger.info("🔍 MECHANICS DEBUG: Filtering for mechanic IDs: #{inspect(mechanic_ids)}")
        
        Enum.filter(original_items, fn item ->
          if item.mechanics do
            item_mechanic_ids = Enum.map(item.mechanics, & &1.id)
            has_all = Enum.all?(mechanic_ids, fn id -> id in item_mechanic_ids end)
            if has_all do
              Logger.debug("🔍 #{item.primary_name} has all required mechanics")
            end
            has_all
          else
            # Item has no mechanics loaded, can't match
            false
          end
        end)
      end
    
    Logger.info("🔍 MECHANICS DEBUG: Filtered to #{length(filtered_items)} items")
    
    # Update the filtered collection and pagination
    total_items = length(filtered_items)
    current_page_items = get_current_page_items_from_list(filtered_items, socket.assigns.current_page)
    
    socket
    |> assign(:all_collection_items, filtered_items)
    |> assign(:collection_items, current_page_items)
    |> assign(:total_items, total_items)
  end

  # Helper function to parse URL parameters into filters
  defp parse_url_filters(params) do
    %{}
    |> maybe_put_filter(:primary_name, Map.get(params, "primary_name"))
    |> maybe_put_filter(:players, Map.get(params, "players"))
    |> maybe_put_filter(:playingtime, Map.get(params, "playingtime"))
    |> maybe_put_filter(:average, Map.get(params, "average"))
    |> maybe_put_filter(:rank, Map.get(params, "rank"))
    |> put_weight_filters(
      Map.get(params, "averageweight_min"),
      Map.get(params, "averageweight_max")
    )
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

    # Add modal_thing_id parameter if needed
    query_params =
      if opts[:modal_thing_id] do
        Map.put(query_params, "modal_thing_id", to_string(opts[:modal_thing_id]))
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

  # Helper function to parse sort parameters from URL
  defp parse_sort_params(params) do
    sort_field =
      case Map.get(params, "sort_by") do
        "primary_name" -> :primary_name
        "players" -> :players
        "average" -> :average
        "averageweight" -> :averageweight
        # default
        _ -> :primary_name
      end

    sort_direction =
      case Map.get(params, "sort_direction") do
        "desc" -> :desc
        # default to ascending
        _ -> :asc
      end

    {sort_field, sort_direction}
  end

  # Helper function to build URL with filter, sort, and page query parameters
  defp build_collection_url_with_sort_and_page(username, filters, sort_field, sort_direction, opts) do
    base_path = "/collection/#{username}"

    # Build query parameters
    query_params =
      filters
      |> Enum.filter(fn {_key, value} -> value != nil and value != "" end)
      |> Enum.map(fn {key, value} -> {Atom.to_string(key), value} end)
      |> Enum.into(%{})

    # Add sort parameters
    query_params =
      query_params
      |> Map.put("sort_by", Atom.to_string(sort_field))
      |> Map.put("sort_direction", Atom.to_string(sort_direction))

    # Add advanced_search parameter if needed
    query_params =
      if opts[:advanced_search] do
        Map.put(query_params, "advanced_search", "true")
      else
        query_params
      end

    # Add page parameter if needed and not page 1
    query_params =
      if opts[:page] && opts[:page] != 1 do
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

  # Helper function to build URL with filter and sort query parameters  
  defp build_collection_url_with_sort(username, filters, sort_field, sort_direction, opts) do
    base_path = "/collection/#{username}"

    # Build query parameters
    query_params =
      filters
      |> Enum.filter(fn {_key, value} -> value != nil and value != "" end)
      |> Enum.map(fn {key, value} -> {Atom.to_string(key), value} end)
      |> Enum.into(%{})

    # Add sort parameters
    query_params =
      query_params
      |> Map.put("sort_by", Atom.to_string(sort_field))
      |> Map.put("sort_direction", Atom.to_string(sort_direction))

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

    # Add modal_thing_id parameter if needed
    query_params =
      if opts[:modal_thing_id] do
        Map.put(query_params, "modal_thing_id", to_string(opts[:modal_thing_id]))
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
  
  # Helper function to build URL with filter, sort, and mechanics query parameters  
  defp build_collection_url_with_mechanics(username, filters, sort_field, sort_direction, selected_mechanics, opts) do
    base_path = "/collection/#{username}"

    # Build query parameters
    query_params =
      filters
      |> Enum.filter(fn {_key, value} -> value != nil and value != "" end)
      |> Enum.map(fn {key, value} -> {Atom.to_string(key), value} end)
      |> Enum.into(%{})

    # Add sort parameters
    query_params =
      query_params
      |> Map.put("sort_by", Atom.to_string(sort_field))
      |> Map.put("sort_direction", Atom.to_string(sort_direction))
      
    # Add mechanics parameter if any mechanics selected
    query_params =
      if MapSet.size(selected_mechanics) > 0 do
        Map.put(query_params, "mechanics", encode_selected_mechanics(selected_mechanics))
      else
        query_params
      end

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

    # Add modal_thing_id parameter if needed
    query_params =
      if opts[:modal_thing_id] do
        Map.put(query_params, "modal_thing_id", to_string(opts[:modal_thing_id]))
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
