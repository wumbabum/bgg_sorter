defmodule Dispatch do
  @moduledoc """
  Public interface for the Dispatch app.
  Exposes available workers and provides a function to enqueue them.
  """

  @workers [
    %{key: "precache", label: "Precache Top Games", worker: Dispatch.Workers.PrecacheWorker}
  ]

  @doc "Returns the list of workers that can be manually triggered."
  @spec available_workers() :: [%{key: String.t(), label: String.t(), worker: module()}]
  def available_workers, do: @workers

  @doc "Enqueues a worker by its key. Returns {:ok, job} or {:error, reason}."
  @spec run_worker(String.t()) :: {:ok, Oban.Job.t()} | {:error, atom()}
  def run_worker(key) do
    case Enum.find(@workers, &(&1.key == key)) do
      %{worker: worker} -> worker.new(%{}) |> Oban.insert()
      nil -> {:error, :unknown_worker}
    end
  end
end
