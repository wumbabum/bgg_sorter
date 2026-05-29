defmodule Web.AdminJobsLiveTest do
  use Web.ConnCase

  import Phoenix.LiveViewTest

  @moduletag :capture_log

  defp auth_conn(conn) do
    credentials = Base.encode64("admin:changeme")
    put_req_header(conn, "authorization", "Basic #{credentials}")
  end

  describe "GET /admin/jobs" do
    test "requires authentication", %{conn: conn} do
      conn = get(conn, "/admin/jobs")
      assert conn.status == 401
    end

    test "renders with valid credentials and no jobs", %{conn: conn} do
      {:ok, _view, html} = live(auth_conn(conn), "/admin/jobs")

      assert html =~ "Jobs Dashboard"
      assert html =~ "No jobs found"
    end

    test "renders job history table when jobs exist", %{conn: conn} do
      # Insert a completed job directly
      {:ok, _job} =
        Dispatch.Workers.PrecacheWorker.new(%{})
        |> Oban.insert()

      {:ok, _view, html} = live(auth_conn(conn), "/admin/jobs")

      assert html =~ "Jobs Dashboard"
      assert html =~ "PrecacheWorker"
    end

    test "renders Run Job button and worker dropdown", %{conn: conn} do
      {:ok, _view, html} = live(auth_conn(conn), "/admin/jobs")

      assert html =~ "Run Job"
      assert html =~ "Precache Top Games"
    end

    test "clicking Run Job enqueues a job", %{conn: conn} do
      {:ok, view, _html} = live(auth_conn(conn), "/admin/jobs")

      html = render_click(view, "run_job")

      assert html =~ "job enqueued"
      assert html =~ "PrecacheWorker"
    end

    test "renders duration column without crashing", %{conn: conn} do
      # Insert a completed job with attempted_at and completed_at
      {:ok, job} =
        Dispatch.Workers.PrecacheWorker.new(%{})
        |> Oban.insert()

      # Simulate completion by updating the job
      now = DateTime.utc_now()
      started = DateTime.add(now, -30, :second)

      Oban.Job
      |> Core.Repo.get!(job.id)
      |> Ecto.Changeset.change(
        state: "completed",
        attempted_at: started,
        completed_at: now,
        attempt: 1
      )
      |> Core.Repo.update!()

      {:ok, _view, html} = live(auth_conn(conn), "/admin/jobs")

      # Should render duration without crashing
      assert html =~ "30s"
      assert html =~ "Completed"
    end

    test "renders message column for completed jobs with results", %{conn: conn} do
      {:ok, job} =
        Dispatch.Workers.PrecacheWorker.new(%{})
        |> Oban.insert()

      now = DateTime.utc_now()

      Oban.Job
      |> Core.Repo.get!(job.id)
      |> Ecto.Changeset.change(
        state: "completed",
        attempted_at: now,
        completed_at: now,
        attempt: 1,
        meta: %{"results" => %{"total_requested" => 0, "total_cached" => 0, "total_failed" => 0}}
      )
      |> Core.Repo.update!()

      {:ok, _view, html} = live(auth_conn(conn), "/admin/jobs")

      assert html =~ "All games cached"
    end

    test "prefers meta.message over derived results message", %{conn: conn} do
      {:ok, job} =
        Dispatch.Workers.PrecacheWorker.new(%{})
        |> Oban.insert()

      now = DateTime.utc_now()

      Oban.Job
      |> Core.Repo.get!(job.id)
      |> Ecto.Changeset.change(
        state: "completed",
        attempted_at: now,
        completed_at: now,
        attempt: 1,
        meta: %{
          "status" => "ok",
          "message" => "Cached 7 of 10 games",
          "results" => %{
            "total_requested" => 10,
            "total_cached" => 7,
            "total_failed" => 0
          }
        }
      )
      |> Core.Repo.update!()

      {:ok, _view, html} = live(auth_conn(conn), "/admin/jobs")

      assert html =~ "Cached 7 of 10 games"
      assert html =~ "✅ Completed"
    end

    test "shows first line of Oban error for discarded jobs (not 'Unknown error')",
         %{conn: conn} do
      {:ok, job} =
        Dispatch.Workers.PrecacheWorker.new(%{})
        |> Oban.insert()

      now = DateTime.utc_now()

      # Match Oban's actual on-disk shape for the errors column.
      oban_error = %{
        "at" => DateTime.to_iso8601(now),
        "attempt" => 1,
        "error" =>
          "** (File.Error) could not stream \"/app/missing.csv\": no such file or directory\n    (elixir 1.15.6) lib/file/stream.ex:94: anonymous fn/3 in Enumerable.File.Stream.reduce/3"
      }

      Oban.Job
      |> Core.Repo.get!(job.id)
      |> Ecto.Changeset.change(
        state: "discarded",
        attempted_at: now,
        discarded_at: now,
        attempt: 1,
        errors: [oban_error]
      )
      |> Core.Repo.update!()

      {:ok, _view, html} = live(auth_conn(conn), "/admin/jobs")

      # Show the first line of the actual error string, not a generic fallback.
      assert html =~ "File.Error"
      assert html =~ "could not stream"
      refute html =~ "Unknown error"
    end

    test "shows warning badge when completed job recorded status=error", %{conn: conn} do
      {:ok, job} =
        Dispatch.Workers.PrecacheWorker.new(%{})
        |> Oban.insert()

      now = DateTime.utc_now()

      Oban.Job
      |> Core.Repo.get!(job.id)
      |> Ecto.Changeset.change(
        state: "completed",
        attempted_at: now,
        completed_at: now,
        attempt: 1,
        meta: %{
          "status" => "error",
          "message" => "Cached 2 of 5; 3 failed",
          "results" => %{
            "total_requested" => 5,
            "total_cached" => 2,
            "total_failed" => 3
          }
        }
      )
      |> Core.Repo.update!()

      {:ok, _view, html} = live(auth_conn(conn), "/admin/jobs")

      assert html =~ "Completed with errors"
      assert html =~ "Cached 2 of 5; 3 failed"
    end
  end
end
