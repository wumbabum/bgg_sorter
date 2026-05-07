defmodule Dispatch.Workers.PrecacheWorkerTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Core.Repo

  import Mox

  alias Dispatch.Workers.PrecacheWorker

  @moduletag :capture_log

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Core.Repo, shared: false)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :verify_on_exit!
    :ok
  end

  defp mock_things_xml(things) do
    items =
      Enum.map(things, fn %{id: id, name: name} ->
        ~s(<item type="boardgame" id="#{id}">
            <name type="primary" sortindex="1" value="#{name}" />
            <yearpublished value="2024" />
            <minplayers value="2" />
            <maxplayers value="4" />
            <playingtime value="60" />
            <statistics>
              <ratings>
                <average value="8.0" />
                <ranks>
                  <rank type="subtype" id="1" name="boardgame" value="100" />
                </ranks>
              </ratings>
            </statistics>
          </item>)
      end)
      |> Enum.join("")

    ~s(<?xml version="1.0" encoding="utf-8"?>
       <items totalitems="#{length(things)}">#{items}</items>)
  end

  describe "perform/1" do
    test "fetches and caches uncached games" do
      # Mock the BGG API to return game data
      Core.MockReqClient
      |> expect(:get, fn _url, _params, _headers ->
        {:ok, %Req.Response{status: 200, body: mock_things_xml([
          %{id: "224517", name: "Brass: Birmingham"},
          %{id: "342942", name: "Ark Nova"}
        ])}}
      end)

      # Run with limit of 2 to keep test fast
      job = %Oban.Job{id: 1, args: %{"limit" => 2}, meta: %{}}

      assert :ok = PrecacheWorker.perform(job)

      # Verify games were cached
      assert Core.Repo.get(Core.Schemas.Thing, "224517") != nil
      assert Core.Repo.get(Core.Schemas.Thing, "342942") != nil
    end

    test "records results in job meta" do
      Core.MockReqClient
      |> expect(:get, fn _url, _params, _headers ->
        {:ok, %Req.Response{status: 200, body: mock_things_xml([
          %{id: "224517", name: "Brass: Birmingham"}
        ])}}
      end)

      # Insert a real Oban job so we can verify meta update
      {:ok, oban_job} =
        %{"limit" => 1}
        |> PrecacheWorker.new()
        |> Oban.insert()

      assert :ok = PrecacheWorker.perform(oban_job)

      # Reload job and check meta
      updated_job = Core.Repo.get!(Oban.Job, oban_job.id)
      results = updated_job.meta["results"]

      assert is_map(results)
      assert results["total_cached"] >= 0
      assert results["completed_at"] != nil
    end

    test "handles zero uncached games gracefully" do
      # Pre-cache all top games so nothing is uncached
      # With limit=0, no API calls should be made
      job = %Oban.Job{id: 1, args: %{"limit" => 0}, meta: %{}}

      # No mock expectations — if it tries to call API, Mox will fail
      assert :ok = PrecacheWorker.perform(job)
    end
  end
end
