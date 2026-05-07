defmodule Web.PrecacheDashboardLive do
  @moduledoc """
  Dashboard for viewing past precache cron job runs.
  """

  use Web, :live_view

  import Ecto.Query

  @refresh_interval_ms 30_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_interval_ms)

    {:ok, assign(socket, :jobs, load_jobs())}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval_ms)
    {:noreply, assign(socket, :jobs, load_jobs())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="max-width: 960px; margin: 40px auto; font-family: sans-serif;">
      <h1 style="font-size: 24px; margin-bottom: 20px;">Precache Job History</h1>
      <p style="color: #666; font-size: 12px; margin-bottom: 16px;">
        Auto-refreshes every 30 seconds. Showing last 30 days of runs.
      </p>

      <%= if Enum.empty?(@jobs) do %>
        <p style="color: #999;">No precache jobs found.</p>
      <% else %>
        <table style="width: 100%; border-collapse: collapse; font-size: 14px;">
          <thead>
            <tr style="border-bottom: 2px solid #ddd; text-align: left;">
              <th style="padding: 8px;">Date</th>
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
    from(j in "oban_jobs",
      where: j.worker == "Dispatch.Workers.PrecacheWorker",
      order_by: [desc: j.inserted_at],
      limit: 50,
      select: %{
        id: j.id,
        state: j.state,
        inserted_at: j.inserted_at,
        attempt: j.attempt,
        max_attempts: j.max_attempts,
        meta: j.meta
      }
    )
    |> Core.Repo.all()
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
