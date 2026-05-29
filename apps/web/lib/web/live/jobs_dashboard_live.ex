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
              <th style="padding: 8px;">Duration</th>
              <th style="padding: 8px;">Cached</th>
              <th style="padding: 8px;">Message</th>
              <th style="padding: 8px;">Attempt</th>
            </tr>
          </thead>
          <tbody>
            <%= for job <- @jobs do %>
              <tr style="border-bottom: 1px solid #eee;">
                <td style="padding: 8px;"><%= format_datetime(job.inserted_at) %></td>
                <td style="padding: 8px;"><%= short_worker_name(job.worker) %></td>
                <td style="padding: 8px;"><%= status_badge(job) %></td>
                <td style="padding: 8px;"><%= format_duration(job) %></td>
                <td style="padding: 8px;"><%= get_result(job, "total_cached") %></td>
                <td style="padding: 8px; max-width: 300px; overflow: hidden; text-overflow: ellipsis;"><%= job_message(job) %></td>
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
        attempted_at: j.attempted_at,
        completed_at: j.completed_at,
        attempt: j.attempt,
        max_attempts: j.max_attempts,
        meta: j.meta,
        errors: j.errors
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

  # A job that finished cleanly from Oban's perspective can still record
  # `meta["status"] == "error"` for partial-success runs (e.g. some BGG
  # chunks failed). Surface that as a distinct ⚠️ badge so the operator
  # notices without needing to read the Message column.
  defp status_badge(%{state: "completed", meta: %{"status" => "error"}}),
    do: "⚠️ Completed with errors"

  defp status_badge(%{state: state}), do: state_badge(state)

  defp state_badge("completed"), do: "✅ Completed"
  defp state_badge("executing"), do: "🔄 Running"
  defp state_badge("available"), do: "⏳ Queued"
  defp state_badge("scheduled"), do: "📅 Scheduled"
  defp state_badge("retryable"), do: "❌ Failed"
  defp state_badge("discarded"), do: "❌ Failed"
  defp state_badge("cancelled"), do: "🚫 Cancelled"
  defp state_badge(state), do: state

  defp format_duration(%{state: "executing", attempted_at: started}) when not is_nil(started) do
    seconds = NaiveDateTime.diff(NaiveDateTime.utc_now(), started, :second)
    format_seconds(seconds) <> "..."
  end

  defp format_duration(%{attempted_at: started, completed_at: finished})
       when not is_nil(started) and not is_nil(finished) do
    format_seconds(NaiveDateTime.diff(finished, started, :second))
  end

  defp format_duration(_), do: "—"

  defp format_seconds(s) when s < 60, do: "#{s}s"
  defp format_seconds(s) when s < 3600, do: "#{div(s, 60)}m #{rem(s, 60)}s"
  defp format_seconds(s), do: "#{div(s, 3600)}h #{div(rem(s, 3600), 60)}m"

  # Prefer the worker's own message from meta. Fall back to Oban's
  # auto-populated errors when the worker crashed (raise/exit/throw)
  # before it could record anything. Finally, derive a message from
  # the legacy `results` map for jobs that ran before Dispatch.Result
  # was introduced.
  defp job_message(%{meta: %{"message" => msg}}) when is_binary(msg) and msg != "", do: msg

  defp job_message(%{state: state, errors: errors})
       when state in ["retryable", "discarded"] and is_list(errors) and errors != [] do
    # Oban stores entries as %{"at" => _, "attempt" => _, "error" => formatted}
    # where `error` is the full "** (ExceptionType) msg\n    stack..." string.
    # Show just the first line (the exception + its message); the truncated
    # stack trace prefix from the previous version was useless in the table.
    raw = errors |> List.last() |> Map.get("error") || "Unknown error"

    raw
    |> String.split("\n", parts: 2)
    |> List.first()
    |> String.slice(0, 200)
  end

  defp job_message(%{meta: meta}) when is_map(meta) do
    results = Map.get(meta, "results", %{})

    parts = []
    parts = if results["end_of_list"], do: ["Reached end of list" | parts], else: parts
    parts = if results["total_failed"] && results["total_failed"] > 0, do: ["#{results["total_failed"]} failed" | parts], else: parts
    parts = if results["total_requested"] == 0, do: ["All games cached" | parts], else: parts

    case parts do
      [] -> "—"
      _ -> Enum.join(parts, ", ")
    end
  end

  defp job_message(_), do: "—"

  defp get_result(%{meta: meta}, key) when is_map(meta) do
    case get_in(meta, ["results", key]) do
      nil -> "—"
      value -> value
    end
  end

  defp get_result(_, _), do: "—"
end
