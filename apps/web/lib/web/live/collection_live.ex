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
      |> assign(:pending_modal_thing_id, nil)
      |> assign(:pending_refilter, nil)
      |> assign(:cache_progress, %{loaded: 0, total: 0})
      |> assign(:background_loading, false)
      |> assign(:stale_remaining, 0)
      |> assign(:all_thing_ids, [])

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
      |> assign(:pending_modal_thing_id, nil)
      |> assign(:pending_refilter, nil)
      |> assign(:cache_progress, %{loaded: 0, total: 0})
      |> assign(:background_loading, false)
      |> assign(:stale_remaining, 0)
      |> assign(:all_thing_ids, [])

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

    Logger.info(
      "🔍 PARAMS DEBUG: advanced_search from URL=#{advanced_search}, current=#{socket.assigns.advanced_search}"
    )

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

    sort_changed? =
      sort_field != current_sort_field or sort_direction != current_sort_direction

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

      # Filters changed (but same username), try client-side filtering first.
      # Sync ALL URL-derived assigns before invoking the cache so that any
      # simultaneous change to sort or mechanics is honored too. Without this,
      # the cond fall-through silently dropped sort/mechanics updates that
      # arrived alongside filter changes.
      filters != current_filters ->
        socket =
          socket
          |> assign(:current_page, page)
          |> assign(:advanced_search, advanced_search)
          |> assign(:sort_by, sort_field)
          |> assign(:sort_direction, sort_direction)
          |> assign(:selected_mechanics, selected_mechanics)
          |> assign(:modal_thing_id, modal_thing_id)
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

      # Selected mechanics changed (and filters unchanged).
      selected_mechanics != current_selected_mechanics ->
        Logger.info("🔍 MECHANICS DEBUG: Mechanics changed, applying client-side filtering")

        # Sync sort assigns from URL so a concurrent sort change in the same
        # URL update is captured. Without this the cond fall-through silently
        # dropped sort updates that arrived alongside mechanics changes.
        socket =
          socket
          |> assign(:selected_mechanics, selected_mechanics)
          |> assign(:advanced_search, advanced_search)
          |> assign(:modal_thing_id, modal_thing_id)
          |> assign(:sort_by, sort_field)
          |> assign(:sort_direction, sort_direction)

        # If sort ALSO changed, the cached items must be re-sorted via the
        # cache layer; pure client-side filtering would preserve the old order.
        # If only mechanics changed, client-side filtering is sufficient and
        # cheaper. Either path uses apply_client_side_filters / the cache to
        # combine the active filters with the new mechanics selection so other
        # filters (average, primary_name, ...) survive.
        socket =
          if sort_changed? do
            socket =
              socket
              |> assign(:collection_loading, true)
              |> assign(:search_error, nil)

            case reapply_filters_to_collection(socket, socket.assigns.filters) do
              {:ok, s} ->
                s

              {:reload_needed, s} ->
                send(self(), {:load_collection_with_filters, username, s.assigns.filters})
                s
            end
          else
            then(socket, &apply_client_side_filters(&1, &1.assigns.filters))
          end

        socket = assign(socket, :current_page, 1)

        # Preserve modal state if modal_thing_id is present
        socket =
          if modal_thing_id && modal_thing_id != "" && modal_thing_id != current_modal_thing_id do
            socket
            |> assign(:modal_open, true)
            |> assign(:modal_loading, true)
            |> tap(fn _ -> send(self(), {:load_modal_details_by_id, modal_thing_id}) end)
          else
            socket
          end

        {:noreply, socket}

      # Sort parameters changed - re-sort existing cached data.
      # Sync mechanics from URL so the cache query uses the latest value.
      sort_changed? ->
        original_items = socket.assigns.original_collection_items

        socket =
          socket
          |> assign(:sort_by, sort_field)
          |> assign(:sort_direction, sort_direction)
          # Reset to page 1
          |> assign(:current_page, 1)
          |> assign(:advanced_search, advanced_search)
          |> assign(:selected_mechanics, selected_mechanics)
          |> assign(:modal_thing_id, modal_thing_id)
          |> assign(:collection_loading, true)
          |> assign(:search_error, nil)

        if Enum.empty?(original_items) do
          # No cached data available - reload from BGG API
          Logger.info("No cached data available for sorting, reloading from API")
          send(self(), {:load_collection_with_filters, username, filters})
          {:noreply, socket}
        else
          # Re-sort existing cached data using database operations
          Logger.info(
            "Re-sorting #{length(original_items)} cached items with new sort: #{sort_field} #{sort_direction}"
          )

          # Extract client-only filters and add selected mechanics
          client_filters = extract_client_only_filters(filters)

          client_filters_with_mechanics =
            Map.put(
              client_filters,
              :selected_mechanics,
              MapSet.to_list(socket.assigns.selected_mechanics)
            )

          # Capture LiveView PID
          liveview_pid = self()

          # Use async Task to re-sort with database-level operations
          _task =
            Task.async(fn ->
              try do
                case Core.BggCacher.load_things_cache(
                       original_items,
                       client_filters_with_mechanics,
                       sort_field,
                       sort_direction
                     ) do
                  {:ok, items} ->
                    send(liveview_pid, {:cache_loaded, self(), items})
                    {:ok, items}

                  {:error, reason} = error ->
                    send(liveview_pid, {:cache_error, self(), reason})
                    error
                end
              rescue
                error ->
                  send(liveview_pid, {:cache_error, self(), {:exception, error}})
                  {:error, {:exception, error}}
              end
            end)

          # Task will send {:cache_loaded, task_pid, sorted_items} message
          {:noreply, socket}
        end

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
    bgg_params = convert_filters_to_bgg_params(filters)
    Logger.info("BGG API params: #{inspect(bgg_params)}")

    with {:ok, %CollectionResponse{items: basic_items}} <-
           Core.BggGateway.collection(username, bgg_params) do
      thing_ids = Enum.map(basic_items, & &1.id)

      socket =
        socket
        |> assign(:all_thing_ids, thing_ids)
        |> assign(:cache_progress, %{loaded: 0, total: length(basic_items)})

      liveview_pid = self()

      # Use Task.start (not Task.async) so the task survives LiveView disconnect.
      # If the user leaves mid-load, the task keeps running and caches things in DB
      # for future sessions. Messages to the dead LiveView PID are silently dropped.
      Task.start(fn ->
        try do
          with {:ok, stale_ids} <- Core.BggCacher.get_stale_thing_ids(thing_ids) do
            # Send cached things immediately
            Core.BggCacher.get_all_cached_things(
              thing_ids, %{}, :primary_name, :asc,
              notify_pid: liveview_pid
            )

            # Tell LiveView how many stale items to expect
            send(liveview_pid, {:stale_count, length(stale_ids)})

            # Fetch stale things progressively — sends {:chunk_cached, things} per chunk
            Core.BggCacher.update_stale_things(
              stale_ids,
              notify_pid: liveview_pid
            )
          else
            {:error, reason} ->
              send(liveview_pid, {:cache_error, self(), reason})
          end
        rescue
          error ->
            Logger.error("Cache loading crashed: #{inspect(error)}")
            send(liveview_pid, {:cache_error, self(), {:exception, error}})
        catch
          kind, value ->
            Logger.error("Cache loading caught #{kind}: #{inspect(value)}")
            send(liveview_pid, {:cache_error, self(), {kind, value}})
        end
      end)

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
  def handle_info({:cached_things_loaded, things}, socket) do
    Logger.info("Received #{length(things)} cached things for immediate display")

    client_filters = extract_client_only_filters(socket.assigns.filters)

    socket =
      socket
      |> assign(:original_collection_items, things)
      |> assign(:collection_loading, false)
      |> assign(:search_error, nil)
      |> apply_client_side_filters(client_filters)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:stale_count, count}, socket) do
    socket =
      if count > 0 do
        socket
        |> assign(:background_loading, true)
        |> assign(:stale_remaining, count)
      else
        socket
        |> assign(:background_loading, false)
        |> assign(:stale_remaining, 0)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:chunk_cached, chunk_things}, socket) do
    Logger.info("Received chunk with #{length(chunk_things)} newly cached things")

    all_thing_ids = socket.assigns.all_thing_ids
    stale_remaining = max(0, socket.assigns.stale_remaining - length(chunk_things))

    # Re-query DB for proper sort order with all accumulated IDs
    sort_field = socket.assigns.sort_by
    sort_direction = socket.assigns.sort_direction

    {:ok, sorted_things} =
      Core.BggCacher.get_all_cached_things(all_thing_ids, %{}, sort_field, sort_direction)

    client_filters = extract_client_only_filters(socket.assigns.filters)

    socket =
      socket
      |> assign(:original_collection_items, sorted_things)
      |> assign(:stale_remaining, stale_remaining)
      |> apply_client_side_filters(client_filters)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:stale_updates_complete}, socket) do
    Logger.info("All stale updates complete")

    # Final re-query to ensure everything is sorted correctly
    all_thing_ids = socket.assigns.all_thing_ids
    sort_field = socket.assigns.sort_by
    sort_direction = socket.assigns.sort_direction

    {:ok, sorted_things} =
      Core.BggCacher.get_all_cached_things(all_thing_ids, %{}, sort_field, sort_direction)

    client_filters = extract_client_only_filters(socket.assigns.filters)

    socket =
      socket
      |> assign(:original_collection_items, sorted_things)
      |> assign(:background_loading, false)
      |> assign(:stale_remaining, 0)
      |> apply_client_side_filters(client_filters)

    {:noreply, socket}
  end

  @impl true
  def handle_info({ref, {:ok, _items}}, socket) when is_reference(ref) do
    # Task completion message - ignore since we handle our own messages
    Process.demonitor(ref, [:flush])
    {:noreply, socket}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    # Task monitoring message - already handled via our error messages
    {:noreply, socket}
  end

  @impl true
  def handle_info({:cache_loaded, _task_pid, items}, socket) do
    # Check what type of load this is
    pending_modal_id = Map.get(socket.assigns, :pending_modal_thing_id)
    pending_refilter = Map.get(socket.assigns, :pending_refilter)

    cond do
      # Modal loading - single item expected
      pending_modal_id != nil and length(items) == 1 ->
        [detailed_thing] = items
        Logger.info("Loaded modal details for: #{inspect(detailed_thing.primary_name)}")

        socket =
          socket
          |> assign(:modal_loading, false)
          |> assign(:thing_details, detailed_thing)
          |> assign(:selected_thing, detailed_thing)
          |> assign(:modal_error, nil)
          |> assign(:pending_modal_thing_id, nil)

        {:noreply, socket}

      # Modal loading but no items found
      pending_modal_id != nil ->
        socket =
          socket
          |> assign(:modal_loading, false)
          |> assign(:modal_error, "Game not found in your collection")
          |> assign(:pending_modal_thing_id, nil)

        {:noreply, socket}

      # Re-filter/re-sort operation on existing data
      pending_refilter != nil ->
        Logger.info("Received re-filtered/sorted data with #{length(items)} items")

        # Update pagination
        total_items = length(items)
        current_page_items = get_current_page_items_from_list(items, socket.assigns.current_page)

        socket =
          socket
          |> assign(:filters, pending_refilter)
          |> assign(:all_collection_items, items)
          |> assign(:collection_items, current_page_items)
          |> assign(:total_items, total_items)
          |> assign(:collection_loading, false)
          |> assign(:pending_refilter, nil)

        {:noreply, socket}

      # Main collection loading (original unfiltered data)
      true ->
        Logger.info("Received cache_loaded message with #{length(items)} unfiltered cached items")

        # Extract client-only filters
        client_filters = extract_client_only_filters(socket.assigns.filters)

        # Now apply filters client-side to get the filtered results
        socket =
          socket
          # Store original unfiltered data for client-side filtering
          |> assign(:original_collection_items, items)
          |> assign(:collection_loading, false)
          |> assign(:search_error, nil)
          # Apply all filters client-side (including mechanics)
          |> apply_client_side_filters(client_filters)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:cache_error, _task_pid, reason}, socket) do
    error_message = format_error_message(reason)
    Logger.warning("Failed to load cached things: #{inspect(reason)}")

    # Check if this was for modal or main collection
    pending_modal_id = Map.get(socket.assigns, :pending_modal_thing_id)

    socket =
      if pending_modal_id != nil do
        # Modal error
        socket
        |> assign(:modal_loading, false)
        |> assign(:modal_error, "Failed to load game details: #{error_message}")
        |> assign(:pending_modal_thing_id, nil)
      else
        # Collection error
        socket
        |> assign(:collection_loading, false)
        |> assign(:search_error, error_message)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:load_modal_details_by_id, thing_id}, socket) do
    # Try to parse the thing_id
    case Integer.parse(to_string(thing_id)) do
      {parsed_id, _} ->
        # Create a minimal thing struct to query with
        minimal_thing = %{id: to_string(parsed_id)}

        # Capture LiveView PID
        liveview_pid = self()

        # Start async Task for modal loading
        _task =
          Task.async(fn ->
            try do
              case Core.BggCacher.load_things_cache([minimal_thing]) do
                {:ok, items} ->
                  send(liveview_pid, {:cache_loaded, self(), items})
                  {:ok, items}

                {:error, reason} = error ->
                  send(liveview_pid, {:cache_error, self(), reason})
                  error
              end
            rescue
              error ->
                send(liveview_pid, {:cache_error, self(), {:exception, error}})
                {:error, {:exception, error}}
            end
          end)

        # Task will send {:cache_loaded, task_pid, items} or {:cache_error, task_pid, reason}
        # Store thing_id in socket to identify this is for modal
        socket = assign(socket, :pending_modal_thing_id, to_string(parsed_id))
        {:noreply, socket}

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
    Logger.info(
      "Loading modal details for thing: #{inspect(thing.primary_name)} (ID: #{thing.id})"
    )

    # Capture LiveView PID
    liveview_pid = self()

    # Start async Task for modal loading
    _task =
      Task.async(fn ->
        try do
          case Core.BggCacher.load_things_cache([thing]) do
            {:ok, items} ->
              send(liveview_pid, {:cache_loaded, self(), items})
              {:ok, items}

            {:error, reason} = error ->
              send(liveview_pid, {:cache_error, self(), reason})
              error
          end
        rescue
          error ->
            send(liveview_pid, {:cache_error, self(), {:exception, error}})
            {:error, {:exception, error}}
        end
      end)

    # Task will send {:cache_loaded, task_pid, items} or {:cache_error, task_pid, reason}
    # Store thing_id in socket to identify this is for modal
    socket = assign(socket, :pending_modal_thing_id, thing.id)
    {:noreply, socket}
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

      # Build URL preserving sort and mechanics from current socket state
      collection_url =
        build_collection_url_with_mechanics(
          username,
          filters,
          socket.assigns.sort_by,
          socket.assigns.sort_direction,
          socket.assigns.selected_mechanics,
          advanced_search: true
        )

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

        # Build URL with no filters but preserving sort and mechanics.
        # advanced_search is also preserved if currently active.
        url =
          build_collection_url_with_mechanics(
            username,
            %{},
            socket.assigns.sort_by,
            socket.assigns.sort_direction,
            socket.assigns.selected_mechanics,
            advanced_search: socket.assigns.advanced_search
          )

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
        {:noreply, push_patch(socket, to: pagination_url(socket, page))}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("next_page", _params, socket) do
    max_page = max_page(socket)
    current_page = socket.assigns.current_page

    if current_page < max_page do
      {:noreply, push_patch(socket, to: pagination_url(socket, current_page + 1))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("prev_page", _params, socket) do
    current_page = socket.assigns.current_page

    if current_page > 1 do
      {:noreply, push_patch(socket, to: pagination_url(socket, current_page - 1))}
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
          selected_mechanics = socket.assigns.selected_mechanics

          # Preserve sort and mechanics state so the modal URL is shareable and
          # refreshing it does not silently drop those parameters.
          url =
            build_collection_url_with_mechanics(
              username,
              filters,
              sort_field,
              sort_direction,
              selected_mechanics,
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
        selected_mechanics = socket.assigns.selected_mechanics

        url =
          build_collection_url_with_mechanics(
            username,
            filters,
            sort_field,
            sort_direction,
            selected_mechanics,
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

    Logger.info("🔄 TOGGLE DEBUG: current=#{current_advanced_search}, new=#{new_advanced_search}")

    case socket.assigns.username do
      nil ->
        # No username, update URL and state with push_patch for smoother experience
        url =
          if new_advanced_search do
            "/collection?advanced_search=true"
          else
            "/collection"
          end

        socket = assign(socket, :advanced_search, new_advanced_search)
        {:noreply, push_patch(socket, to: url)}

      username ->
        # Have username and collection data, just toggle advanced search with push_patch.
        # Preserve ALL current URL state (filters, page, sort, mechanics) -- the
        # mechanics-aware builder is used so selected mechanics survive the toggle.
        filters = socket.assigns.filters
        current_page = socket.assigns.current_page
        sort_field = socket.assigns.sort_by
        sort_direction = socket.assigns.sort_direction
        selected_mechanics = socket.assigns.selected_mechanics

        new_url =
          build_collection_url_with_mechanics(
            username,
            filters,
            sort_field,
            sort_direction,
            selected_mechanics,
            page: current_page,
            advanced_search: new_advanced_search
          )

        Logger.info(
          "🌐 URL DEBUG: new_advanced_search=#{new_advanced_search}, generated URL=#{new_url}"
        )

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
  def handle_event("immediate_filter", %{"field" => field, "value" => value}, socket) do
    # Handle immediate filtering for form fields (except username changes) - text/number inputs format
    username = socket.assigns.username

    apply_immediate_filter(socket, username, field, value)
  end

  @impl true
  def handle_event("immediate_filter", params, socket) when is_map(params) do
    # Handle immediate filtering for dropdown selects - form data format
    username = socket.assigns.username

    # Extract field and value from form data format (e.g., %{"players" => "3", "_target" => ["players"]})
    case Enum.find(params, fn {key, _value} -> key != "_target" end) do
      {field, value} when is_binary(field) and is_binary(value) ->
        apply_immediate_filter(socket, username, field, value)

      _ ->
        Logger.warning("Unknown immediate_filter format: #{inspect(params)}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_mechanic", %{"mechanic_id" => "all"}, socket) do
    # "All" toggles the mechanics expansion, doesn't clear selection
    current_expanded = Map.get(socket.assigns, :all_mechanics_expanded, false)
    new_expanded = !current_expanded

    socket = assign(socket, :all_mechanics_expanded, new_expanded)

    # Load popular mechanics if expanding and not already loaded
    socket =
      if new_expanded and Enum.empty?(socket.assigns.popular_mechanics) do
        Logger.info("Loading popular mechanics")
        # Set loading state first
        socket = assign(socket, :mechanics_loading, true)

        try do
          # Get popular mechanics from database
          popular_mechanics = Core.Repo.all(Core.Schemas.Mechanic.most_popular(150))

          # If no popular mechanics found, try loading seeded mechanics alphabetically
          final_mechanics =
            if Enum.empty?(popular_mechanics) do
              Core.Repo.all(from(m in Core.Schemas.Mechanic, limit: 50, order_by: m.name))
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
                Core.Repo.all(from(m in Core.Schemas.Mechanic, limit: 50, order_by: m.name))
              rescue
                _ -> []
              end

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
    # Toggle mechanic in selected_mechanics set
    current_selected = socket.assigns.selected_mechanics

    new_selected =
      if MapSet.member?(current_selected, mechanic_id) do
        MapSet.delete(current_selected, mechanic_id)
      else
        MapSet.put(current_selected, mechanic_id)
      end

    # Reapply ALL filters together (not just mechanics) so any active
    # primary_name / average / players / weight filters survive a mechanic
    # toggle in the rendered view.
    socket =
      socket
      |> assign(:selected_mechanics, new_selected)
      |> then(&apply_client_side_filters(&1, &1.assigns.filters))
      # Reset to page 1 when filtering changes
      |> assign(:current_page, 1)

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

        url =
          build_collection_url_with_mechanics(
            username,
            filters,
            sort_field,
            sort_direction,
            new_selected,
            # Always reset to page 1 when filtering
            page: 1,
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

    # Update URL to include sort parameters (this will trigger handle_params
    # with new sort). The mechanics-aware builder is used so any selected
    # mechanics are preserved when the user clicks a sortable column header.
    username = socket.assigns.username
    filters = socket.assigns.filters
    advanced_search = socket.assigns.advanced_search
    selected_mechanics = socket.assigns.selected_mechanics

    url =
      build_collection_url_with_mechanics(
        username,
        filters,
        field,
        new_sort_direction,
        selected_mechanics,
        advanced_search: advanced_search
      )

    {:noreply, push_patch(socket, to: url)}
  end

  # Build a pagination URL that preserves all current URL state: filters,
  # sort, mechanics, and advanced_search.
  defp pagination_url(socket, page) do
    build_collection_url_with_mechanics(
      socket.assigns.username,
      socket.assigns.filters,
      socket.assigns.sort_by,
      socket.assigns.sort_direction,
      socket.assigns.selected_mechanics,
      page: page,
      advanced_search: socket.assigns.advanced_search
    )
  end

  # Common logic for applying immediate filters
  defp apply_immediate_filter(socket, username, field, value) do
    if username do
      # Extract current filters and update with new field value
      current_filters = socket.assigns.filters

      updated_filters =
        case field do
          "players" ->
            put_filter_always(current_filters, :players, value)

          "primary_name" ->
            put_filter_always(current_filters, :primary_name, value)

          "playingtime" ->
            put_filter_always(current_filters, :playingtime, value)

          "average" ->
            put_filter_always(current_filters, :average, value)

          "rank" ->
            put_filter_always(current_filters, :rank, value)

          "description" ->
            put_filter_always(current_filters, :description, value)

          "averageweight_min" ->
            put_weight_filters(
              current_filters,
              value,
              Map.get(current_filters, :averageweight_max)
            )

          "averageweight_max" ->
            put_weight_filters(
              current_filters,
              Map.get(current_filters, :averageweight_min),
              value
            )

          _ ->
            current_filters
        end

      # All immediate filters update the URL so the state is shareable and
      # survives page refresh. URL is built via the mechanics-aware builder
      # so sort and selected_mechanics are preserved.
      filter_url =
        build_collection_url_with_mechanics(
          username,
          updated_filters,
          socket.assigns.sort_by,
          socket.assigns.sort_direction,
          socket.assigns.selected_mechanics,
          # Reset to page 1 when filtering
          page: 1,
          advanced_search: socket.assigns.advanced_search
        )

      # Apply immediate filtering using client-side filtering (no database hit)
      original_items = socket.assigns.original_collection_items

      if Enum.empty?(original_items) do
        # No original data available - need to reload from BGG API and database
        Logger.info(
          "No original collection data available for immediate filter, reloading from API"
        )

        socket =
          socket
          |> assign(:collection_loading, true)
          |> assign(:search_error, nil)

        # Reload collection with new filters
        send(self(), {:load_collection_with_filters, username, updated_filters})

        {:noreply, push_patch(socket, to: filter_url)}
      else
        # Use client-side filtering for instant results (no database hit)
        Logger.info("Applied immediate filter for #{field}=#{value} using client-side filtering")

        updated_socket =
          socket
          |> apply_client_side_filters(updated_filters)
          # Reset to page 1 when filtering
          |> assign(:current_page, 1)

        {:noreply, push_patch(updated_socket, to: filter_url)}
      end
    else
      # No username, can't filter
      {:noreply, socket}
    end
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

  defp format_error_message(:max_retries_exceeded),
    do: "BGG servers are currently unavailable. Please try again in a few minutes."

  defp format_error_message(:not_found),
    do: "Collection not found. Please check the username and try again."

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
    # These filters are applied at database level for better performance.
    # :average is included so the minimum rating filter applies to cached data
    # without requiring a fresh BGG API collection reload.
    client_only_keys = [
      :primary_name,
      :players,
      :playingtime,
      :rank,
      :average,
      :averageweight_min,
      :averageweight_max,
      :description,
      :selected_mechanics
    ]

    Map.take(filters, client_only_keys)
  end

  # Try to apply filters using the cached database data first, fallback to BGG API if needed
  defp reapply_filters_to_collection(socket, new_filters) do
    original_items = socket.assigns.original_collection_items

    if Enum.empty?(original_items) do
      # No original data available - need to reload from BGG API
      {:reload_needed, socket}
    else
      # We have original data - use BggCacher with database-level filtering and sorting
      Logger.info("Applying filters using database cache with #{length(original_items)} items")

      # Extract client-only filters and convert mechanics to proper format
      client_filters = extract_client_only_filters(new_filters)

      client_filters_with_mechanics =
        Map.put(
          client_filters,
          :selected_mechanics,
          MapSet.to_list(socket.assigns.selected_mechanics)
        )

      # Capture LiveView PID
      liveview_pid = self()

      # Use async Task to apply database-level filtering and sorting
      _task =
        Task.async(fn ->
          try do
            case Core.BggCacher.load_things_cache(
                   original_items,
                   client_filters_with_mechanics,
                   socket.assigns.sort_by,
                   socket.assigns.sort_direction
                 ) do
              {:ok, items} ->
                send(liveview_pid, {:cache_loaded, self(), items})
                {:ok, items}

              {:error, reason} = error ->
                send(liveview_pid, {:cache_error, self(), reason})
                error
            end
          rescue
            error ->
              send(liveview_pid, {:cache_error, self(), {:exception, error}})
              {:error, {:exception, error}}
          end
        end)

      # Store the new filters so we know this is a re-filter operation
      socket = assign(socket, :pending_refilter, new_filters)

      # Task will send {:cache_loaded, task_pid, filtered_items} message
      {:ok, socket}
    end
  end

  # Add non-empty values to filter map
  defp maybe_put_filter(filters, _key, value) when value in [nil, ""], do: filters
  defp maybe_put_filter(filters, key, value), do: Map.put(filters, key, value)

  # Always put filter value (even if empty) - used for immediate filtering
  defp put_filter_always(filters, key, value) when value in [nil, ""] do
    # Remove empty filters instead of storing them
    Map.delete(filters, key)
  end

  defp put_filter_always(filters, key, value), do: Map.put(filters, key, value)

  # Always put weight filters (even if nil/empty) and let Thing.filter_by handle defaults
  defp put_weight_filters(filters, min_weight, max_weight) do
    filters
    |> Map.put(:averageweight_min, min_weight)
    |> Map.put(:averageweight_max, max_weight)
  end

  # Put mechanics filters from comma-separated string or MapSet
  defp put_mechanics_filters(filters, mechanics_str)
       when is_binary(mechanics_str) and mechanics_str != "" do
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
        from(m in Core.Schemas.Mechanic,
          where: ilike(m.name, ^like_pattern),
          order_by: m.name,
          limit: 15
        )
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

  # Apply all filters to the collection using pure client-side filtering (no database hits)
  defp apply_client_side_filters(socket, filters) do
    original_items = socket.assigns.original_collection_items
    selected_mechanics = socket.assigns.selected_mechanics

    # Combine regular filters with mechanics selection
    all_filters = Map.put(filters, :selected_mechanics, MapSet.to_list(selected_mechanics))

    # Use Thing.filter_by/2 for pure client-side filtering
    filtered_items = Core.Schemas.Thing.filter_by(original_items, all_filters)

    # Update pagination
    total_items = length(filtered_items)

    current_page_items =
      get_current_page_items_from_list(filtered_items, socket.assigns.current_page)

    socket
    |> assign(:filters, filters)
    |> assign(:all_collection_items, filtered_items)
    |> assign(:collection_items, current_page_items)
    |> assign(:total_items, total_items)
    |> assign(:collection_loading, false)
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
  defp build_collection_url_with_sort_and_page(
         username,
         filters,
         sort_field,
         sort_direction,
         opts
       ) do
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
  defp build_collection_url_with_mechanics(
         username,
         filters,
         sort_field,
         sort_direction,
         selected_mechanics,
         opts
       ) do
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
