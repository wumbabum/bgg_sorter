defmodule DispatchTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Core.Repo

  @moduletag :capture_log

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Core.Repo, shared: false)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  describe "available_workers/0" do
    test "returns a list of worker definitions" do
      workers = Dispatch.available_workers()

      assert is_list(workers)
      assert length(workers) >= 1

      first = hd(workers)
      assert Map.has_key?(first, :key)
      assert Map.has_key?(first, :label)
      assert Map.has_key?(first, :worker)
    end

    test "includes precache worker" do
      workers = Dispatch.available_workers()
      keys = Enum.map(workers, & &1.key)

      assert "precache" in keys
    end
  end

  describe "run_worker/1" do
    test "inserts an Oban job for a valid worker key" do
      assert {:ok, %Oban.Job{} = job} = Dispatch.run_worker("precache")
      assert job.worker == "Dispatch.Workers.PrecacheWorker"
      assert job.state == "available"
    end

    test "returns error for unknown worker key" do
      assert {:error, :unknown_worker} = Dispatch.run_worker("nonexistent")
    end
  end
end
