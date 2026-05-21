defmodule Dispatch.Result do
  @moduledoc """
  Standardized job-result recording for the jobs dashboard.

  Oban itself does not persist the return value of `perform/1`; it only
  uses it for control flow. To surface a status and short message in the
  admin dashboard, workers call `record/4` near the end of `perform/1`,
  writing to `oban_jobs.meta` directly.

  The convention is:

    * `meta["status"]`  - either `"ok"` or `"error"`.
    * `meta["message"]` - a short human-readable string.
    * `meta["recorded_at"]` - ISO8601 UTC timestamp set automatically.
    * `meta[<other>]`   - any extra worker-specific data passed in via `extra`.

  Workers that raise/exit/throw never reach this call. For those cases
  the dashboard falls back to Oban's auto-populated `errors` column.
  """

  require Logger

  @type status :: :ok | :error

  @doc """
  Records a status and message on the Oban job's `meta`, merging any
  extra worker-specific data, and broadcasts `:job_updated` so dashboards
  refresh in real time.

  Returns `:ok` even on persistence failure (logs the error); the worker's
  own return value is what determines retry behavior in Oban.
  """
  @spec record(Oban.Job.t(), status(), String.t(), map()) :: :ok
  def record(%Oban.Job{id: id, meta: existing_meta}, status, message, extra \\ %{})
      when status in [:ok, :error] and is_binary(message) and is_map(extra) do
    new_meta =
      existing_meta
      |> Map.merge(extra)
      |> Map.put("status", Atom.to_string(status))
      |> Map.put("message", message)
      |> Map.put("recorded_at", DateTime.utc_now() |> DateTime.to_iso8601())

    Oban.Job
    |> Core.Repo.get!(id)
    |> Ecto.Changeset.change(meta: new_meta)
    |> Core.Repo.update!()

    Phoenix.PubSub.broadcast(Web.PubSub, "dispatch:jobs", :job_updated)
    :ok
  rescue
    error ->
      Logger.error("Failed to record job result for job #{id}: #{inspect(error)}")
      :ok
  end
end
