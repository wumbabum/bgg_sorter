defmodule Dispatch.Workers.PrecacheWorker do
  @moduledoc """
  Daily cron worker that precaches top-ranked BGG games.
  """

  use Oban.Worker, queue: :precache, max_attempts: 1

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    # TODO: implement in commit 4
    :ok
  end
end
