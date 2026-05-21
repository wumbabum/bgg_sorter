defmodule Dispatch.ResultTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Core.Repo, shared: false)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  defp insert_job do
    {:ok, job} =
      Dispatch.Workers.PrecacheWorker.new(%{})
      |> Oban.insert()

    job
  end

  describe "record/4" do
    test "writes status, message, and recorded_at to job meta on :ok" do
      job = insert_job()

      assert :ok = Dispatch.Result.record(job, :ok, "All done")

      reloaded = Core.Repo.get!(Oban.Job, job.id)
      assert reloaded.meta["status"] == "ok"
      assert reloaded.meta["message"] == "All done"
      assert is_binary(reloaded.meta["recorded_at"])
    end

    test "writes status \"error\" and message on :error" do
      job = insert_job()

      assert :ok = Dispatch.Result.record(job, :error, "BGG unreachable")

      reloaded = Core.Repo.get!(Oban.Job, job.id)
      assert reloaded.meta["status"] == "error"
      assert reloaded.meta["message"] == "BGG unreachable"
    end

    test "merges extra map into meta alongside status and message" do
      job = insert_job()

      assert :ok =
               Dispatch.Result.record(job, :ok, "Cached 5 games", %{
                 "results" => %{"total_cached" => 5, "total_failed" => 0}
               })

      reloaded = Core.Repo.get!(Oban.Job, job.id)
      assert reloaded.meta["status"] == "ok"
      assert reloaded.meta["message"] == "Cached 5 games"
      assert reloaded.meta["results"]["total_cached"] == 5
    end

    test "preserves existing meta keys not touched by the call" do
      job = insert_job()

      Oban.Job
      |> Core.Repo.get!(job.id)
      |> Ecto.Changeset.change(meta: %{"existing" => "value"})
      |> Core.Repo.update!()

      reloaded = Core.Repo.get!(Oban.Job, job.id)

      assert :ok = Dispatch.Result.record(reloaded, :ok, "done")

      after_record = Core.Repo.get!(Oban.Job, job.id)
      assert after_record.meta["existing"] == "value"
      assert after_record.meta["status"] == "ok"
    end

    test "raises on invalid status atom" do
      job = insert_job()

      assert_raise FunctionClauseError, fn ->
        Dispatch.Result.record(job, :pending, "nope")
      end
    end

    test "raises on non-binary message" do
      job = insert_job()

      assert_raise FunctionClauseError, fn ->
        Dispatch.Result.record(job, :ok, :done)
      end
    end

    test "returns :ok and logs even when the job no longer exists in the DB" do
      # Build a fake Oban.Job struct with an id that does not exist.
      fake_job = %Oban.Job{id: -1, meta: %{}, args: %{}, worker: "Anything"}

      assert :ok = Dispatch.Result.record(fake_job, :ok, "ghost")
    end
  end
end
