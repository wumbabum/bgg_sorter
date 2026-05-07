defmodule Web.JobsDashboardLive do
  @moduledoc """
  Admin dashboard for viewing and triggering dispatch jobs.
  """

  use Web, :live_view

  import Ecto.Query

  @refresh_interval_ms 30_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Process.send_after(self(), :refresh, @refresh_interval_ms)
      Phoenix.PubSub.subscribe(Web.PubSub, "dispatch:jobs")
    end

    workers = Dispatch.available_workers()
    default_key = if workers != [], do: hd(workers).key, else: nil

    socket =
      socket
      |> assign(:jobs, load_jobs())
      |> assign(:workers, workers)
      |> assign(:selected_worker, default_key)
      |> assign(:flash_message, nil)

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval_ms)
    {:noreply, assign(socket, :jobs, load_jobs())}
  end

  @impl true
  def handle_info(:job_updated, socket) do
    {:noreply, assign(socket, :jobs, load_jobs())}
  end

  @impl true
  def handle_event("select_worker", %{"worker" => key}, socket) do
    {:noreply, assign(socket, :selected_worker, key)}
  end

  @impl true
  def handle_event("run_job", _params, socket) do
    case Dispatch.run_worker(socket.assigns.selected_worker) do
      {:ok, _job} ->
        label = get_worker_label(socket.assigns.workers, socket.assigns.selected_worker)

        socket =
          socket
          |> assign(:jobs, load_jobs())
          |> assign(:flash_message, "#{label} job enqueued")

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, :flash_message, "Failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="max-width: 960px; margin: 40px auto; font-family: sans-serif;">
      <h1 style="font-size: 24px; margin-bottom: 20px;">Jobs Dashboard</h1>

      <div style="display: flex; gap: 8px; align-items: center; margin-bottom: 24px;">
        <form phx-change="select_worker" style="display: flex; gap: 8px; align-items: center;">
          <select name="worker" style="padding: 6px 12px; border: 1px solid #ccc; border-radius: 4px; font-size: 14px;">
            <%= for w <- @workers do %>
              <option value={w.key} selected={w.key == @selected_worker}><%= w.label %></option>
            <% end %>
          </select>
        </form>
        <button phx-click="run_job" style="padding: 6px 16px; background: #3f3f74; color: white; border: none; border-radius: 4px; font-size: 14px; cursor: pointer;">
          Run Job
        </button>
        <%= if @flash_message do %>
          <span style="color: #666; font-size: 13px;"><%= @flash_message %></span>
        <% end %>
      </div>

      <h2 style="font-size: 18px; margin-bottom: 12px;">Job History</h2>
      <p style="color: #666; font-size: 12px; margin-bottom: 16px;">
        Auto-refreshes every 30 seconds.
      </p>

      <%= if Enum.empty?(@jobs) do %>
        <p style="color: #999;">No jobs found.</p>
      <% else %>
        <table style="width: 100%; border-collapse: collapse; font-size: 14px;">
          <thead>
            <tr style="border-bottom: 2px solid #ddd; text-align: left;">
              <th style="padding: 8px;">Date</th>
              <th style="padding: 8px;">Worker</th>
              <th style="padding: 8px;">Status</th>
              <th style="padding: 8px;">Requested</th>
              <th style="padding: 8px;">Cached</th>
              <th style="padding: 8px;">Failed</th>
              <th style="padding: 8px;">Attempt</th>
            </tr>
          </thead>
          <tbody>
            <%= for job <- @jobs do %>
              <tr style="border-bottom: 1px solid #eee;">
                <td style="padding: 8px;"><%= format_datetime(job.inserted_at) %></td>
                <td style="padding: 8px;"><%= short_worker_name(job.worker) %></td>
                <td style="padding: 8px;"><%= status_badge(job.state) %></td>
                <td style="padding: 8px;"><%= get_result(job, "total_requested") %></td>
                <td style="padding: 8px;"><%= get_result(job, "total_cached") %></td>
                <td style="padding: 8px;"><%= get_result(job, "total_failed") %></td>
                <td style="padding: 8px;"><%= job.attempt %>/<%= job.max_attempts %></td>
              </tr>
            <% end %>
          </tbody>
        </table>
      <% end %>
    </div>
    """
  end

  defp load_jobs do
    worker_names =
      Dispatch.available_workers()
      |> Enum.map(fn w -> Kernel.inspect(w.worker) |> String.replace("Elixir.", "") end)

    from(j in "oban_jobs",
      where: j.worker in ^worker_names,
      order_by: [desc: j.inserted_at],
      limit: 50,
      select: %{
        id: j.id,
        worker: j.worker,
        state: j.state,
        inserted_at: j.inserted_at,
        attempt: j.attempt,
        max_attempts: j.max_attempts,
        meta: j.meta
      }
    )
    |> Core.Repo.all()
  end

  defp get_worker_label(workers, key) do
    case Enum.find(workers, &(&1.key == key)) do
      %{label: label} -> label
      _ -> key
    end
  end

  defp short_worker_name(worker) do
    worker |> String.split(".") |> List.last()
  end

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  end

  defp status_badge("completed"), do: "✅ Completed"
  defp status_badge("executing"), do: "🔄 Running"
  defp status_badge("available"), do: "⏳ Queued"
  defp status_badge("scheduled"), do: "📅 Scheduled"
  defp status_badge("retryable"), do: "🔁 Retryable"
  defp status_badge("discarded"), do: "❌ Discarded"
  defp status_badge("cancelled"), do: "🚫 Cancelled"
  defp status_badge(state), do: state

  defp get_result(%{meta: meta}, key) when is_map(meta) do
    case get_in(meta, ["results", key]) do
      nil -> "—"
      value -> value
    end
  end

  defp get_result(_, _), do: "—"
end
